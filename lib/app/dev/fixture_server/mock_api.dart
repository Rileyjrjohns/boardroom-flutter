import 'dart:convert';
import 'dart:typed_data';

import 'package:boardroom/app/dev/fixture_server/api_message.dart';
import 'package:boardroom/app/dev/in_memory/in_memory_auth_session.dart';
import 'package:boardroom/app/dev/in_memory/in_memory_backend.dart';
import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/domain/value_objects/page_cursor.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/core/infrastructure/http/protocol.dart';
import 'package:boardroom/core/infrastructure/shared/rejection_schemas.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/domain/value_objects/email_address.dart';
import 'package:boardroom/features/auth/infrastructure/dto/session_dto.dart';
import 'package:boardroom/features/documents/infrastructure/dto/document_dto.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/infrastructure/dto/meeting_dto.dart';
import 'package:boardroom/features/votes/infrastructure/dto/vote_dto.dart';
import 'package:meta/meta.dart';

/// The `code` of the body of an error: `{ "error": { "code": "..." } }`.
/// Documented in docs/api.md.
enum ApiErrorCode implements StableValue {
  /// The request is malformed: a parameter, a body, a header.
  badRequest('badRequest'),

  /// The email and the password are refused.
  invalidCredentials('invalidCredentials'),

  /// No valid token.
  unauthorized('unauthorized'),

  /// The token is valid, the user may not have this item.
  forbidden('forbidden'),

  /// There is no such route or item.
  notFound('notFound'),

  /// The service cannot take the request now.
  serviceUnavailable('serviceUnavailable'),

  /// The server failed.
  unexpected('unexpected');

  new(this.value);

  @override
  final String value;
}

const int _millisPerSecond = 1000;

/// What a `limit` is written as: whole decimal digits, no sign, no space, no
/// exponent, no leading zero. `int.tryParse` alone would take " 10", "+5" and
/// "0x10" for numbers.
final RegExp _limitFormat = RegExp(r'^(0|[1-9][0-9]*)$');

const String _errorKey = 'error';
const String _codeKey = 'code';

/// What the simulated API is built with.
@immutable
final class MockApiOptions {
  /// Creates the options of an API.
  const new({
    required this.backend,
    required this.clock,
    required this.accounts,
    required this.sessionLifetime,
    required this.generateToken,
  });

  /// The simulated server: the rules, and the content. The API is a window on
  /// it.
  final InMemoryBackend backend;

  /// The clock of the server: the sessions it grants expire on it.
  final Clock clock;

  /// The accounts that can sign in.
  final List<DemoAccount> accounts;

  /// How long a token lasts, from the sign-in. Whole seconds are what the API
  /// says.
  final DurationMillis sessionLifetime;

  /// A token that nobody can guess. Given from outside, because this layer
  /// holds no randomness.
  final String Function() generateToken;
}

enum _RouteName {
  signIn,
  listMeetings,
  getMeeting,
  getDocument,
  getDocumentContent,
  castVote,
}

/// What a request amounts to once the path and the method are read.
@immutable
final class _Route {
  const new(this.name, [this.id]);

  final _RouteName name;
  final String? id;
}

/// The caller of a request: the session its token stands for, or nobody.
final class _TokenCaller implements Caller {
  const new(this._session);

  final Session? _session;

  @override
  Future<Result<Session?, StorageReadFailedError>> current() =>
      Future.value(ok<Session?>(_session));
}

/// The HTTP API of docs/api.md, served from the simulated server. It is a
/// function from an [ApiRequest] to an [ApiResponse] and knows no network
/// library: the adapter of the fixture server gives it to dio, and the tests
/// call it directly, so one implementation of the rules serves both. The
/// business rules are not here: the routes only read the request, authenticate
/// it from its token, ask the `InMemoryBackend`, and write its answer the way
/// the API says.
final class MockApi {
  /// Creates the API of [_options].
  new(this._options);

  final MockApiOptions _options;
  final Map<String, Session> _sessions = {};

  /// The server forgets every token it granted: the next request of each holder
  /// is refused.
  void revokeSessions() {
    _sessions.clear();
  }

  /// Answers [request]: whatever it holds, the answer is a status and a body.
  Future<ApiResponse> handle(ApiRequest request) {
    final route = _routeOf(request);
    if (route == null) {
      return Future.value(
        _failure(HttpStatusCode.notFound, ApiErrorCode.notFound),
      );
    }

    return switch (route.name) {
      _RouteName.signIn => _signIn(request),
      _RouteName.listMeetings => _listMeetings(request),
      _RouteName.getMeeting => _getMeeting(request, route.id!),
      _RouteName.getDocument => _getDocument(request, route.id!),
      _RouteName.getDocumentContent => _getDocumentContent(request, route.id!),
      _RouteName.castVote => _castVote(request),
    };
  }

  Future<ApiResponse> _signIn(ApiRequest request) async {
    final body = decodeWire(_readJson(request), SignInRequestWire.fromJson);
    if (body is! Ok<SignInRequestWire, WireFailure>) {
      return _failure(HttpStatusCode.badRequest, ApiErrorCode.badRequest);
    }
    final credentials = body.value;

    final reached = await _options.backend.network.enter();
    if (reached is Err) {
      return _unavailable();
    }

    final email = parseEmailAddress(credentials.email);
    final account = switch (email) {
      Ok(:final value) =>
        _options.accounts
            .where((candidate) => candidate.user.email == value)
            .firstOrNull,
      Err() => null,
    };
    if (account == null || account.password != credentials.password) {
      return _failure(
        HttpStatusCode.unauthorized,
        ApiErrorCode.invalidCredentials,
      );
    }

    final lifetimeSeconds = _options.sessionLifetime ~/ _millisPerSecond;
    final expiresAt = andThen(
      durationFromMillis(lifetimeSeconds * _millisPerSecond),
      (lifetime) => plus(_options.clock.now(), lifetime),
    );
    if (expiresAt is! Ok<Instant, ValidationError>) {
      return _failure(
        HttpStatusCode.internalServerError,
        ApiErrorCode.unexpected,
      );
    }

    final session = createSession(
      user: account.user,
      expiresAt: expiresAt.value,
    );
    final token = _options.generateToken();
    _sessions[token] = session;
    return _json(
      HttpStatusCode.ok,
      toSignInResponseWire(
        SignedIn(token: token, session: session),
        lifetimeSeconds,
      ).toJson(),
    );
  }

  Future<ApiResponse> _listMeetings(ApiRequest request) async {
    final query = _queryOf(request);
    final period = parseMeetingPeriod(query[QueryParameter.period.value] ?? '');
    final rawCursor = query[QueryParameter.cursor.value];
    final cursor = rawCursor == null ? null : parsePageCursor(rawCursor);
    final rawLimit = query[QueryParameter.limit.value] ?? '';
    final limit = _limitFormat.hasMatch(rawLimit)
        ? (int.tryParse(rawLimit) ?? double.nan)
        : double.nan;
    if (period is! Ok<MeetingPeriod, ValidationError> || cursor is Err) {
      return _failure(HttpStatusCode.badRequest, ApiErrorCode.badRequest);
    }
    final page = createPageRequest(
      limit: limit,
      cursor: switch (cursor) {
        Ok<PageCursor, ValidationError>(:final value) => value,
        _ => null,
      },
    );
    if (page is! Ok<PageRequest, ValidationError>) {
      return _failure(HttpStatusCode.badRequest, ApiErrorCode.badRequest);
    }

    final answer = await _options.backend.listMeetings(
      period.value,
      page.value,
      _callerOf(request),
    );
    return switch (answer) {
      Ok(:final value) => _json(
        HttpStatusCode.ok,
        toMeetingPageWire(value).toJson(),
      ),
      // The only way the simulated server refuses a listing it can authenticate
      // is a cursor or a limit it does not accept: the request was wrong.
      Err(:final error) =>
        error is UnexpectedError
            ? _failure(HttpStatusCode.badRequest, ApiErrorCode.badRequest)
            : _refusal(error),
    };
  }

  Future<ApiResponse> _getMeeting(ApiRequest request, String rawId) async {
    final id = parseMeetingId(rawId);
    if (id is! Ok<MeetingId, ValidationError>) {
      return _failure(HttpStatusCode.notFound, ApiErrorCode.notFound);
    }

    final answer = await _options.backend.getMeeting(
      id.value,
      _callerOf(request),
    );
    return switch (answer) {
      Ok(:final value) => _json(
        HttpStatusCode.ok,
        toMeetingWire(value).toJson(),
      ),
      Err(:final error) => _refusal(error),
    };
  }

  Future<ApiResponse> _getDocument(ApiRequest request, String rawId) async {
    final id = parseDocumentId(rawId);
    if (id is! Ok<DocumentId, ValidationError>) {
      return _failure(HttpStatusCode.notFound, ApiErrorCode.notFound);
    }

    final answer = await _options.backend.getDocument(
      id.value,
      _callerOf(request),
    );
    return switch (answer) {
      Ok(:final value) => _json(
        HttpStatusCode.ok,
        toDocumentWire(value).toJson(),
      ),
      Err(:final error) => _refusal(error),
    };
  }

  Future<ApiResponse> _getDocumentContent(
    ApiRequest request,
    String rawId,
  ) async {
    final id = parseDocumentId(rawId);
    if (id is! Ok<DocumentId, ValidationError>) {
      return _failure(HttpStatusCode.notFound, ApiErrorCode.notFound);
    }

    final answer = await _options.backend.fetchDocumentContent(
      id.value,
      _callerOf(request),
    );
    return switch (answer) {
      Ok(:final value) => _pdf(value),
      Err(:final error) => _refusal(error),
    };
  }

  Future<ApiResponse> _castVote(ApiRequest request) async {
    final body = decodeWire(_readJson(request), VoteRequestWire.fromJson);
    final read = switch (body) {
      Ok(:final value) => toVote(value),
      Err() => null,
    };
    final vote = switch (read) {
      Ok(:final value) => value,
      _ => null,
    };
    if (vote == null) {
      return _failure(HttpStatusCode.badRequest, ApiErrorCode.badRequest);
    }
    // The header and the body say the same thing, or the request is not one
    // this server issued.
    final header = request.header(HttpHeader.idempotencyKey.value);
    if (header == null || _decodeOrNull(header) != vote.idempotencyKey) {
      return _failure(HttpStatusCode.badRequest, ApiErrorCode.badRequest);
    }

    final answer = await _options.backend.submitVote(vote, _callerOf(request));
    return switch (answer) {
      Ok() => ApiResponse(
        status: HttpStatusCode.noContent.code,
        headers: _notStored,
        body: Uint8List(0),
      ),
      Err(:final error) =>
        error is VotingError ? _rejection(error) : _refusal(error),
    };
  }

  /// Who the request is from, read from its token when the request is
  /// received. A token the server does not know, or no token, is nobody: the
  /// simulated server then answers `unauthorized`, and checks the expiry of the
  /// session itself.
  Caller _callerOf(ApiRequest request) {
    final header = request.header(HttpHeader.authorization.value);
    final token = header != null && header.startsWith(bearerPrefix)
        ? header.substring(bearerPrefix.length)
        : null;
    return _TokenCaller(token == null ? null : _sessions[token]);
  }
}

_Route? _routeOf(ApiRequest request) {
  final segments = <String>[];
  for (final raw in request.path.split('/')) {
    if (raw.isEmpty) {
      continue;
    }
    final decoded = _decodeOrNull(raw);
    if (decoded == null) {
      return null;
    }
    segments.add(decoded);
  }
  final method = request.method.toUpperCase();
  final root = segments.isNotEmpty ? segments[0] : null;
  final second = segments.length > 1 ? segments[1] : null;
  final third = segments.length > 2 ? segments[2] : null;

  switch (segments.length) {
    case SegmentCount.collection:
      if (root == RouteRoot.meetings.value && method == HttpMethod.get.value) {
        return const _Route(_RouteName.listMeetings);
      }
      if (root == RouteRoot.votes.value && method == HttpMethod.post.value) {
        return const _Route(_RouteName.castVote);
      }
      return null;
    case SegmentCount.item:
      if (root == RouteRoot.auth.value &&
          second == RouteAction.signIn.value &&
          method == HttpMethod.post.value) {
        return const _Route(_RouteName.signIn);
      }
      if (second == null || method != HttpMethod.get.value) {
        return null;
      }
      if (root == RouteRoot.meetings.value) {
        return _Route(_RouteName.getMeeting, second);
      }
      if (root == RouteRoot.documents.value) {
        return _Route(_RouteName.getDocument, second);
      }
      return null;
    case SegmentCount.action:
      return root == RouteRoot.documents.value &&
              second != null &&
              third == RouteAction.content.value &&
              method == HttpMethod.get.value
          ? _Route(_RouteName.getDocumentContent, second)
          : null;
    default:
      return null;
  }
}

/// The text with its percent-encoding undone, or `null` for an encoding that
/// is malformed.
String? _decodeOrNull(String text) {
  try {
    return Uri.decodeComponent(text);
  } on Object {
    return null;
  }
}

/// The text of a query component as `URLSearchParams` reads it: `+` is a space,
/// and an escape sequence that is malformed stays as it was written.
String _decodeQueryComponent(String text) {
  final spaced = text.replaceAll('+', ' ');
  return _decodeOrNull(spaced) ?? spaced;
}

/// The query of the request, by name. When a name is repeated, the first value
/// counts.
Map<String, String> _queryOf(ApiRequest request) {
  final values = <String, String>{};
  for (final pair in request.query.split('&')) {
    if (pair.isEmpty) {
      continue;
    }
    final separator = pair.indexOf('=');
    final name = _decodeQueryComponent(
      separator == -1 ? pair : pair.substring(0, separator),
    );
    final value = separator == -1
        ? ''
        : _decodeQueryComponent(pair.substring(separator + 1));
    values.putIfAbsent(name, () => value);
  }
  return values;
}

/// The JSON a request carries, or `null` when it carries none.
Object? _readJson(ApiRequest request) {
  final body = request.body;
  if (body == null) {
    return null;
  }
  try {
    return jsonDecode(utf8.decode(body));
  } on Object {
    return null;
  }
}

/// Every answer is confidential: nothing between the server and the app may
/// keep a copy.
final Map<String, String> _notStored = {
  HttpHeader.cacheControl.value: cacheControlNoStore,
};

ApiResponse _json(HttpStatusCode status, Object? body) => ApiResponse.text(
  status: status.code,
  text: jsonEncode(body),
  headers: {HttpHeader.contentType.value: mediaTypeJson, ..._notStored},
);

/// The content of a document: the file itself, with the version of the content
/// as its `ETag` (quoted, as the header wants), under the same `no-store` as
/// every other answer.
ApiResponse _pdf(ServedDocumentContent content) => ApiResponse(
  status: HttpStatusCode.ok.code,
  body: content.bytes,
  headers: {
    HttpHeader.contentType.value: mediaTypePdf,
    HttpHeader.eTag.value: '"${content.version}"',
    ..._notStored,
  },
);

ApiResponse _failure(HttpStatusCode status, ApiErrorCode code) =>
    _json(status, {
      _errorKey: {_codeKey: code.value},
    });

ApiResponse _unavailable() => _failure(
  HttpStatusCode.serviceUnavailable,
  ApiErrorCode.serviceUnavailable,
);

/// The business rejection of a vote: 422, and the rule that refused it.
ApiResponse _rejection(VotingError error) => _json(
  HttpStatusCode.unprocessableContent,
  {_errorKey: toVotingErrorWire(error).toJson()},
);

/// The status of a refusal of the simulated server.
ApiResponse _refusal(AppError error) => switch (error) {
  UnauthorizedError() => _failure(
    HttpStatusCode.unauthorized,
    ApiErrorCode.unauthorized,
  ),
  ForbiddenError() => _failure(
    HttpStatusCode.forbidden,
    ApiErrorCode.forbidden,
  ),
  NotFoundError() => _failure(HttpStatusCode.notFound, ApiErrorCode.notFound),
  NetworkUnavailableError() => _unavailable(),
  _ => _failure(HttpStatusCode.internalServerError, ApiErrorCode.unexpected),
};
