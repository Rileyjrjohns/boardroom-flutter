import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/shared/validation.dart';
import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/infrastructure/http/dto/wire.dart';
import 'package:boardroom/infrastructure/http/invalid_response.dart';
import 'package:boardroom/infrastructure/http/protocol.dart';
import 'package:boardroom/infrastructure/http/status_cause.dart';
import 'package:boardroom/infrastructure/http/well_formed.dart';
import 'package:boardroom/infrastructure/shared/issue_paths.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

/// The token of the signed-in user, with the user it belongs to.
@immutable
final class BearerToken {
  /// Creates the token of [userId].
  const new({required this.token, required this.userId});

  /// The bearer token.
  final String token;

  /// The user the token was issued to.
  final UserId userId;

  @override
  bool operator ==(Object other) =>
      other is BearerToken && other.token == token && other.userId == userId;

  @override
  int get hashCode => Object.hash(token, userId);

  // The token is a secret: it never appears in a log.
  @override
  String toString() => 'BearerToken(userId: $userId)';
}

/// Where a request gets the token of the signed-in user, at the moment the
/// request is created. The token comes with the user it belongs to, read in one
/// go, so that a request made for a user can check it is carrying that user's
/// token and not somebody else's (see `HttpRequestSpec.forUser`).
abstract interface class BearerTokenSource {
  /// The token and its user, or `null` when nobody is signed in.
  Future<Result<BearerToken?, StorageReadFailedError>> token();
}

/// The options of the client.
@immutable
final class HttpClientOptions {
  /// Creates the options. The [adapter] replaces the one dio picks for the
  /// platform: the development build gives the one that serves the fixtures, a
  /// test of the client itself gives a scripted one.
  const new({
    required this.baseUrl,
    required this.timeout,
    required this.tokens,
    required this.monitoring,
    this.adapter,
  });

  /// The address of the API, with no trailing slash (see `parseApiBaseUrl`).
  final String baseUrl;

  /// How long a request may take, answer included. A request that takes longer
  /// is a failure.
  final DurationMillis timeout;

  /// Where a request gets the token of the signed-in user.
  final BearerTokenSource tokens;

  /// Where the answers that do not have the shape of the API are reported.
  final Monitoring monitoring;

  /// What carries the requests, in place of the adapter dio picks.
  final HttpClientAdapter? adapter;
}

/// A request is given as a function that builds the description of it. The
/// function runs where the client can catch it: a path made of an identifier
/// that cannot be encoded is a request that cannot be built (`unexpected`), not
/// an exception.
typedef Described<Spec> = Spec Function();

/// What every request says; the ones that read their answer add the shape they
/// expect.
@immutable
class HttpActionSpec {
  /// Creates the description of a request.
  const new({
    required this.method,
    required this.path,
    required this.resource,
    this.query = const {},
    this.body,
    this.headers = const {},
    this.authenticated = true,
    this.forUser,
  });

  /// The method of the request.
  final HttpMethod method;

  /// Starts with a slash. See `Routes`.
  final String path;

  /// The query: a name and its value, left out when the value is `null`.
  final Map<String, Object?> query;

  /// Sent as JSON. `null` is no body.
  final Object? body;

  /// More headers, which win over the ones the client sets.
  final Map<String, String> headers;

  /// Whether the request carries the token of the signed-in user. By default it
  /// does.
  final bool authenticated;

  /// The user the request is made for. The token the client attaches must be
  /// this user's: when it is another's, or nobody's, the answer is
  /// `unauthorized` and nothing is sent. The token and its user are read
  /// together, so a sign-in between the check of the caller and the request
  /// cannot make the request travel under somebody else's session.
  final UserId? forUser;

  /// What is asked for, for the logs.
  final HttpResource resource;
}

/// A request whose answer is read through a [decode] function.
@immutable
final class HttpRequestSpec<T> extends HttpActionSpec {
  /// Creates the description of a request and of the answer it expects.
  const new({
    required super.method,
    required super.path,
    required super.resource,
    required this.decode,
    super.query,
    super.body,
    super.headers,
    super.authenticated,
    super.forUser,
  });

  /// Reads the body of a success, decoded from JSON, or says where it broke the
  /// shape the caller expects. An empty body is `null`.
  final Result<T, WireFailure> Function(Object? body) decode;
}

/// A request for a file: bytes instead of JSON. It is always made for the
/// signed-in user.
@immutable
final class HttpDownloadSpec {
  /// Creates the description of a download.
  const new({
    required this.method,
    required this.path,
    required this.resource,
    required this.mediaType,
    required this.maxBytes,
    this.query = const {},
    this.body,
    this.headers = const {},
    this.timeout,
  });

  /// The method of the request.
  final HttpMethod method;

  /// Starts with a slash. See `Routes`.
  final String path;

  /// The query: a name and its value, left out when the value is `null`.
  final Map<String, Object?> query;

  /// Sent as JSON. `null` is no body.
  final Object? body;

  /// More headers, which win over the ones the client sets.
  final Map<String, String> headers;

  /// What is asked for, for the logs.
  final HttpResource resource;

  /// The media type the answer must have, without parameters
  /// (`application/pdf`). It is also what the request says it accepts. An
  /// answer of another type is refused without being read.
  final String mediaType;

  /// The most bytes the answer may have: one that declares more is refused
  /// unread.
  final int maxBytes;

  /// How long the whole download may take. Defaults to the timeout of the
  /// client.
  final DurationMillis? timeout;
}

/// What a download brought: the bytes, the version the server gave them, and
/// who they are for.
@immutable
final class Downloaded {
  /// Creates what a download brought.
  const new({required this.bytes, required this.etag, required this.userId});

  /// The body of the answer.
  final Uint8List bytes;

  /// The `ETag` of the answer, as it came, or `null` when there was none.
  final String? etag;

  /// The user whose token the request carried: the content is the one for that
  /// user.
  final UserId userId;
}

/// Everything a request can end with, short of a success.
@immutable
sealed class HttpFailure {
  const new();
}

/// The request failed: the network was not there (or the service said it
/// could not take the request now), the caller is not allowed, there is
/// nothing there, or the answer is not one the app can trust. The error is the
/// one of the repositories.
@immutable
final class RequestFailed extends HttpFailure {
  /// Creates the failure that ended with [error].
  const new(this.error);

  /// What the request failed with.
  final RepositoryError error;

  @override
  bool operator ==(Object other) =>
      other is RequestFailed && other.error == error;

  @override
  int get hashCode => Object.hash(RequestFailed, error);

  @override
  String toString() => 'RequestFailed($error)';
}

/// The server understood the request and refused it by a business rule.
@immutable
final class RequestRejected extends HttpFailure {
  /// Creates the rejection described by [error].
  const new(this.error);

  /// The `error` member of the body, which only the caller knows how to read.
  final Object? error;

  @override
  bool operator ==(Object other) =>
      other is RequestRejected &&
      const DeepCollectionEquality().equals(other.error, error);

  @override
  int get hashCode =>
      Object.hash(RequestRejected, const DeepCollectionEquality().hash(error));

  @override
  String toString() => 'RequestRejected($error)';
}

const String _credentialsUnreadable = 'credentials unreadable';
const String _requestNotBuilt = 'request could not be built';
const String _responseTooLarge = 'response too large';
const String _unexpectedMediaType = 'unexpected media type';

const int _successFrom = 200;
const int _successBelow = 300;

const String _queryStart = '?';
const String _querySeparator = '&';
const String _queryAssign = '=';
const String _mediaTypeParameters = ';';
const String _headerValueSeparator = ', ';
const String _errorMember = 'error';

// What the client tells its interceptor about a request, in the `extra` of
// the options of dio.
const String _authenticatedExtra = 'authenticated';
const String _forUserExtra = 'forUser';
const String _userIdExtra = 'userId';

const RequestFailed _networkFailure = RequestFailed(NetworkUnavailableError());

HttpFailure get _tooLarge => RequestFailed(unexpected(_responseTooLarge));

bool _isSuccess(int status) => status >= _successFrom && status < _successBelow;

/// A request that was refused before it was sent, with what it ends with. It
/// travels through dio as the `error` of a `DioException`.
final class _Refused implements Exception {
  const new(this.failure);

  final HttpFailure failure;
}

/// Attaches the token of the signed-in user to the requests that carry one, at
/// the moment they are created. The token comes with the user it belongs to,
/// read in one go: a request made for a user (`forUser`) that finds another's
/// token, or nobody's, is refused here and never sent.
final class _BearerAuthInterceptor extends Interceptor {
  const new(this._tokens);

  final BearerTokenSource _tokens;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[_authenticatedExtra] != true) {
      handler.next(options);
      return;
    }

    final Result<BearerToken?, StorageReadFailedError> read;
    try {
      read = await _tokens.token();
    } on Object {
      _refuse(
        options,
        handler,
        RequestFailed(unexpected(_credentialsUnreadable)),
      );
      return;
    }
    switch (read) {
      case Err():
        _refuse(
          options,
          handler,
          RequestFailed(unexpected(_credentialsUnreadable)),
        );
      case Ok(:final value):
        final forUser = options.extra[_forUserExtra];
        if (value == null || (forUser != null && forUser != value.userId)) {
          _refuse(options, handler, RequestFailed(unauthorized()));
          return;
        }
        options.headers[HttpHeader.authorization.value] =
            '$bearerPrefix${value.token}';
        options.extra[_userIdExtra] = value.userId;
        handler.next(options);
    }
  }

  void _refuse(
    RequestOptions options,
    RequestInterceptorHandler handler,
    HttpFailure failure,
  ) => handler.reject(
    DioException(requestOptions: options, error: _Refused(failure)),
  );
}

/// The answer once its status and its headers are known, and its body not yet
/// read.
final class _Answer {
  const new({
    required this.status,
    required this.headers,
    required this.body,
    required this.userId,
  });

  final int status;
  final Headers headers;
  final Stream<Uint8List> body;
  final UserId? userId;
}

/// What a request got back.
final class _RawResponse {
  const new({
    required this.status,
    required this.userId,
    this.text,
    this.download,
    this.unread = false,
  });

  final int status;

  /// `null` when the body was not read: it was not wanted.
  final String? text;

  /// Whether the body was left alone, so that the connection has to be dropped
  /// for the platform to let go of it.
  final bool unread;

  /// The bytes of a download that succeeded.
  final _DownloadedBytes? download;

  /// The user whose token the request carried.
  final UserId? userId;
}

final class _DownloadedBytes {
  const new({required this.bytes, required this.etag});

  final Uint8List bytes;
  final String? etag;
}

/// How the body of an answer is read, once its status and its headers are
/// known.
typedef _BodyReader = Future<Result<_RawResponse, HttpFailure>> Function(
  _Answer answer,
);

/// The one place that talks to the network: a small client over dio, for the
/// JSON API of the app. It never throws and never hangs.
///
/// - The token of the signed-in user is read when the request is created and
///   attached to it (by an interceptor of dio), so the answer is the one for
///   that user even if somebody else signs in while it is on its way. A request
///   that needs a token and finds none is `unauthorized` without being sent,
///   and so is one made for a user whose token it does not hold (`forUser`).
/// - A request that cannot be built (an identifier that cannot be encoded, a
///   body that has no JSON form) is `unexpected`, and nothing is sent.
/// - Every request refuses redirects and asks that nothing be stored
///   (`Cache-Control: no-store`).
/// - A failure to reach the server, an answer that does not come in time (the
///   request is cancelled) and an answer that is cut off are all
///   `networkUnavailable`, as are the statuses that say the service cannot take
///   the request now: 408, 429, and 502, 503, 504 for a service behind a
///   gateway that cannot be reached.
/// - 401 is `unauthorized`, 403 `forbidden`, 404 `notFound`. 422 is a business
///   rejection: the caller gets the description the server gave, and reads it.
///   Any other status, redirects included, is `unexpected`, whose `cause` is
///   the status and nothing else: no URL, no path, no body.
/// - An answer is read up to `maxResponseBytes`: one that declares more is
///   refused unread, and a body that grows past it stops being read
///   (`unexpected`, cause `response too large`).
/// - The body of a success is checked against the shape the caller gives
///   (`request`), or is not read at all (`perform`). A body that is not JSON or
///   does not match is `unexpected`, and the paths of the fields that did not
///   match (never their values) go to the monitoring.
/// - A file is downloaded with `download`, under the same rules: the same
///   headers, the same token read when the request is created, the same
///   statuses and failures, and the same causes. The answer must be of the
///   media type the caller asks for, which is checked before a byte of the body
///   is read, and it is read up to the size the caller allows. It has its own
///   time limit, since a file takes longer than a page of JSON.
///
/// Nothing is retried here: a request that failed is reported, and the use
/// cases decide whether to ask again.
final class HttpClient {
  /// Creates a client.
  new(HttpClientOptions options) : _options = options, _dio = _dioFor(options);

  final HttpClientOptions _options;
  final Dio _dio;
  bool _closed = false;

  static Dio _dioFor(HttpClientOptions options) {
    final dio = Dio(
      BaseOptions(
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (_) => true,
        responseType: ResponseType.stream,
      ),
    );
    final adapter = options.adapter;
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
    }
    dio.interceptors.add(_BearerAuthInterceptor(options.tokens));
    return dio;
  }

  /// Lets go of the connections the client keeps open. A request made after
  /// that fails like a network that is not there.
  void close() {
    _closed = true;
    _dio.close(force: true);
  }

  /// A request whose answer is read through the decoder of its spec.
  Future<Result<T, HttpFailure>> request<T>(
    Described<HttpRequestSpec<T>> described,
  ) async {
    final HttpRequestSpec<T> spec;
    final RequestOptions prepared;
    try {
      spec = described();
      prepared = _build(
        method: spec.method,
        path: spec.path,
        query: spec.query,
        body: spec.body,
        headers: spec.headers,
        accept: mediaTypeJson,
        authenticated: spec.authenticated,
        forUser: spec.forUser,
      );
    } on Object {
      return err(RequestFailed(unexpected(_requestNotBuilt)));
    }

    final response = await _exchange(
      prepared,
      (answer) => _readText(answer, readsSuccessBody: true),
      _options.timeout,
    );
    return switch (response) {
      Err(:final error) => err(error),
      Ok(:final value) => _interpret(value, (raw) => _readSuccess(spec, raw)),
    };
  }

  /// A request that is done once the server says it succeeded: the body of a
  /// success is not read.
  Future<Result<void, HttpFailure>> perform(
    Described<HttpActionSpec> described,
  ) async {
    final RequestOptions prepared;
    try {
      final spec = described();
      prepared = _build(
        method: spec.method,
        path: spec.path,
        query: spec.query,
        body: spec.body,
        headers: spec.headers,
        accept: mediaTypeJson,
        authenticated: spec.authenticated,
        forUser: spec.forUser,
      );
    } on Object {
      return err(RequestFailed(unexpected(_requestNotBuilt)));
    }

    final response = await _exchange(
      prepared,
      (answer) => _readText(answer, readsSuccessBody: false),
      _options.timeout,
    );
    return switch (response) {
      Err(:final error) => err(error),
      Ok(:final value) => _interpret<void>(value, (_) => ok<void>(null)),
    };
  }

  /// A request for a file, for the signed-in user. The answer's body is not
  /// read unless it is a success of the media type that was asked for, and then
  /// only up to the size that was allowed.
  Future<Result<Downloaded, HttpFailure>> download(
    Described<HttpDownloadSpec> described,
  ) async {
    final HttpDownloadSpec spec;
    final RequestOptions prepared;
    try {
      spec = described();
      prepared = _build(
        method: spec.method,
        path: spec.path,
        query: spec.query,
        body: spec.body,
        headers: spec.headers,
        accept: spec.mediaType,
        authenticated: true,
      );
    } on Object {
      return err(RequestFailed(unexpected(_requestNotBuilt)));
    }

    final response = await _exchange(
      prepared,
      (answer) => _readDownload(answer, spec.mediaType, spec.maxBytes),
      spec.timeout ?? _options.timeout,
    );
    return switch (response) {
      Err(:final error) => err(error),
      Ok(:final value) => _interpret(value, (raw) {
        final download = raw.download;
        final userId = raw.userId;
        if (download == null) {
          return err(RequestFailed(unexpected(statusCause(raw.status))));
        }
        if (userId == null) {
          return err(RequestFailed(unauthorized()));
        }
        return ok(
          Downloaded(
            bytes: download.bytes,
            etag: download.etag,
            userId: userId,
          ),
        );
      }),
    };
  }

  /// The request as it will be sent, but for the token: the address, the
  /// headers (the ones the client sets, `accept` and the caller's own) and the
  /// body. Throws for what cannot be built; the caller catches it.
  RequestOptions _build({
    required HttpMethod method,
    required String path,
    required Map<String, Object?> query,
    required Object? body,
    required Map<String, String> headers,
    required String accept,
    required bool authenticated,
    UserId? forUser,
  }) {
    final json = body == null ? null : jsonEncode(body);
    final address = StringBuffer(_options.baseUrl)
      ..write(requireWellFormed(path))
      ..write(_queryOf(query));
    final sent = <String, String>{
      HttpHeader.accept.value: accept,
      HttpHeader.cacheControl.value: cacheControlNoStore,
      for (final MapEntry(:key, :value) in headers.entries)
        key: requireWellFormed(value),
      if (json != null) HttpHeader.contentType.value: mediaTypeJson,
    };
    return RequestOptions(
      method: method.value,
      path: address.toString(),
      data: json,
      headers: sent,
      responseType: ResponseType.stream,
      followRedirects: false,
      maxRedirects: 0,
      validateStatus: (_) => true,
      extra: {_authenticatedExtra: authenticated, _forUserExtra: ?forUser},
    );
  }

  /// Sends the request and reads the whole answer, within the time allowed.
  Future<Result<_RawResponse, HttpFailure>> _exchange(
    RequestOptions request,
    _BodyReader read,
    DurationMillis timeout,
  ) async {
    final limit = Duration(milliseconds: timeout);
    final cancel = CancelToken();
    final expired = Completer<void>();
    final timer = Timer(limit, () {
      cancel.cancel();
      expired.complete();
    });
    request
      ..cancelToken = cancel
      ..connectTimeout = limit
      ..receiveTimeout = limit;

    try {
      final outcome = await Future.any<Result<_RawResponse, HttpFailure>?>([
        _send(request, cancel, read),
        expired.future.then<Result<_RawResponse, HttpFailure>?>((_) => null),
      ]);
      return outcome ?? err(_networkFailure);
    } finally {
      timer.cancel();
    }
  }

  /// Never fails: whatever goes wrong on the way is a network that failed.
  Future<Result<_RawResponse, HttpFailure>> _send(
    RequestOptions request,
    CancelToken cancel,
    _BodyReader read,
  ) async {
    if (_closed) {
      return err(_networkFailure);
    }
    try {
      final response = await _dio.fetch<ResponseBody>(request);
      final body = response.data;
      final status = response.statusCode;
      if (body == null || status == null) {
        return err(_networkFailure);
      }
      final answer = _Answer(
        status: status,
        headers: response.headers,
        body: body.stream,
        userId: _userIdOf(response.requestOptions),
      );
      final reading = await read(answer);
      // What was not read is dropped with the connection: a failure, the body
      // of a refusal that a download leaves unread, and the body of a success
      // that nobody wants. Cancelling a body that was read to the end changes
      // nothing.
      final left = switch (reading) {
        Err() => true,
        Ok(:final value) => value.unread || !_isSuccess(status),
      };
      if (left) {
        cancel.cancel();
      }
      return reading;
    } on DioException catch (exception) {
      final cause = exception.error;
      return err(cause is _Refused ? cause.failure : _networkFailure);
    } on Object {
      return err(_networkFailure);
    }
  }

  Result<T, HttpFailure> _interpret<T>(
    _RawResponse response,
    Result<T, HttpFailure> Function(_RawResponse response) readSuccess,
  ) {
    final status = response.status;
    if (_isSuccess(status)) {
      return readSuccess(response);
    }
    if (transientStatuses.contains(status)) {
      return err(_networkFailure);
    }

    if (status == HttpStatusCode.unauthorized.code) {
      return err(RequestFailed(unauthorized()));
    }
    if (status == HttpStatusCode.forbidden.code) {
      return err(RequestFailed(forbidden()));
    }
    if (status == HttpStatusCode.notFound.code) {
      return err(RequestFailed(notFound()));
    }
    if (status == HttpStatusCode.unprocessableContent.code) {
      return _readRejection(response.text ?? '') ??
          err(RequestFailed(unexpected(statusCause(status))));
    }
    return err(RequestFailed(unexpected(statusCause(status))));
  }

  Result<T, HttpFailure> _readSuccess<T>(
    HttpRequestSpec<T> spec,
    _RawResponse response,
  ) {
    final monitoring = _options.monitoring;
    final text = trimText(response.text ?? '');
    Object? json;
    if (text.isNotEmpty) {
      try {
        json = jsonDecode(text);
      } on FormatException {
        return err(
          RequestFailed(schemaViolation(monitoring, spec.resource, rootPath)),
        );
      }
    }

    final Result<T, WireFailure> decoded;
    try {
      decoded = spec.decode(json);
    } on Object {
      return err(
        RequestFailed(schemaViolation(monitoring, spec.resource, rootPath)),
      );
    }
    return switch (decoded) {
      Ok(:final value) => ok(value),
      Err(:final error) => err(
        RequestFailed(
          schemaViolation(monitoring, spec.resource, error.issuePaths),
        ),
      ),
    };
  }
}

UserId? _userIdOf(RequestOptions options) {
  final userId = options.extra[_userIdExtra];
  return userId is UserId ? userId : null;
}

String _pairOf(String name, String value) =>
    '${encodeUriComponent(name)}$_queryAssign${encodeUriComponent(value)}';

/// `?name=value&...` with every name and value percent-encoded, or nothing for
/// no parameter.
String _queryOf(Map<String, Object?> query) {
  final pairs = [
    for (final MapEntry(:key, :value) in query.entries)
      if (value != null) _pairOf(key, '$value'),
  ];
  return pairs.isEmpty ? '' : '$_queryStart${pairs.join(_querySeparator)}';
}

/// A header of an answer, as it came, or `null` when there is none.
String? _header(Headers headers, HttpHeader name) =>
    headers[name.value]?.join(_headerValueSeparator);

/// Reads the body as text, up to `maxResponseBytes`. The body of a success is
/// left alone when the caller does not want it.
Future<Result<_RawResponse, HttpFailure>> _readText(
  _Answer answer, {
  required bool readsSuccessBody,
}) async {
  if (_isSuccess(answer.status) && !readsSuccessBody) {
    return ok(
      _RawResponse(status: answer.status, userId: answer.userId, unread: true),
    );
  }
  final text = await _readBounded(answer);
  switch (text) {
    case Ok(:final value):
      return ok(
        _RawResponse(status: answer.status, userId: answer.userId, text: value),
      );
    case Err(:final error):
      return err(error);
  }
}

/// Reads the body of a success as bytes, after checking its media type and the
/// size it declares, both before a byte of it is read. The body of any other
/// answer is not read: only its status matters, and the connection is dropped.
Future<Result<_RawResponse, HttpFailure>> _readDownload(
  _Answer answer,
  String mediaType,
  int maxBytes,
) async {
  if (!_isSuccess(answer.status)) {
    return ok(
      _RawResponse(status: answer.status, userId: answer.userId, unread: true),
    );
  }
  final contentType = _header(answer.headers, HttpHeader.contentType);
  if (_mediaTypeOf(contentType) != mediaType) {
    return err(RequestFailed(unexpected(_unexpectedMediaType)));
  }
  final bytes = await _readBytes(answer, maxBytes);
  switch (bytes) {
    case Ok(:final value):
      return ok(
        _RawResponse(
          status: answer.status,
          userId: answer.userId,
          download: _DownloadedBytes(
            bytes: value,
            etag: _header(answer.headers, HttpHeader.eTag),
          ),
        ),
      );
    case Err(:final error):
      return err(error);
  }
}

/// `application/pdf; charset=binary` is `application/pdf`: the type, lower
/// case, without parameters.
String _mediaTypeOf(String? contentType) =>
    trimText((contentType ?? '').split(_mediaTypeParameters).first)
        .toLowerCase();

/// What the length an answer declares says about it: `null` when it declares
/// none, or something that is not a whole number.
int? _declaredLengthOf(Headers headers) {
  final declared = _header(headers, HttpHeader.contentLength);
  final length = declared == null ? null : num.tryParse(trimText(declared));
  return length != null && length.isFinite && length == length.truncate()
      ? length.toInt()
      : null;
}

/// The bytes of a stream, if they fit in [limit]: the stream is abandoned as
/// soon as it grows past it.
Future<Result<Uint8List, HttpFailure>> _readStream(
  Stream<Uint8List> body,
  int limit,
) async {
  final bytes = BytesBuilder();
  await for (final chunk in body) {
    if (bytes.length + chunk.length > limit) {
      return err(_tooLarge);
    }
    bytes.add(chunk);
  }
  return ok(bytes.takeBytes());
}

/// The body of an answer as bytes, if it fits in [limit]. The length it
/// declares is checked first; then the body is read as a stream, and abandoned
/// as soon as it grows past the limit.
Future<Result<Uint8List, HttpFailure>> _readBytes(
  _Answer answer,
  int limit,
) async {
  final declared = _declaredLengthOf(answer.headers);
  if (declared != null && declared > limit) {
    return err(_tooLarge);
  }
  return await _readStream(answer.body, limit);
}

/// The body of an answer as text, if it fits in `maxResponseBytes`. A body that
/// is not UTF-8 is read with the replacement character, as a browser would.
Future<Result<String, HttpFailure>> _readBounded(_Answer answer) async {
  final bytes = await _readBytes(answer, maxResponseBytes);
  switch (bytes) {
    case Ok(:final value):
      return ok(utf8.decode(value, allowMalformed: true));
    case Err(:final error):
      return err(error);
  }
}

/// The `error` member of the body of a 422, or `null` when the body does not
/// have one.
Result<Never, HttpFailure>? _readRejection(String text) {
  try {
    final body = jsonDecode(text);
    if (body is Map<String, dynamic> && body.containsKey(_errorMember)) {
      return err(RequestRejected(body[_errorMember]));
    }
  } on FormatException {
    // A body that is not JSON is not a description: the caller gets a plain
    // status.
  }
  return null;
}
