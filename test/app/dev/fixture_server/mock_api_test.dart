import 'dart:convert';
import 'dart:typed_data';

import 'package:boardroom/app/dev/fixture_server/api_message.dart';
import 'package:boardroom/app/dev/fixture_server/mock_api.dart';
import 'package:boardroom/app/dev/in_memory/in_memory_backend.dart';
import 'package:boardroom/core/infrastructure/http/protocol.dart';
import 'package:boardroom/features/documents/infrastructure/pdf_signature.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/infrastructure/dto/vote_dto.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/infrastructure/http_world.dart';
import '../../../support/infrastructure/test_server.dart';

// The routes of the API, called directly with an `ApiRequest` and read from the
// `ApiResponse`, with no network and no client: what the HTTP adapters take for
// granted of the server, and what the documentation in docs/api.md promises.
// The adapters are run against it in the tests of the HTTP repositories.

/// What a test reads of an answer.
final class _Answer {
  new(this.response)
    : body = response.header(HttpHeader.contentType.value) == mediaTypeJson
          ? _decoded(response.text)
          : null;

  final ApiResponse response;

  /// The JSON of the answer, or `null` when it has none.
  final Map<String, dynamic>? body;

  int get status => response.status;
  String? get contentType => response.header(HttpHeader.contentType.value);
  String? get cacheControl => response.header(HttpHeader.cacheControl.value);
  String? get etag => response.header(HttpHeader.eTag.value);
  Uint8List get bytes => response.body;
  String get text => response.text;

  static Map<String, dynamic>? _decoded(String text) =>
      text.isEmpty ? null : jsonDecode(text) as Map<String, dynamic>;
}

final class _Server {
  new(this.world) : email = world.accounts.first.user.email, api = world.api;

  final HttpServerSide world;
  final MockApi api;
  final String email;

  Future<_Answer> call(
    String method,
    String path, {
    String? token,
    Object? body,
    String? rawBody,
    Map<String, String> headers = const {},
  }) async {
    final all = {
      ...headers,
      if (token != null) HttpHeader.authorization.value: 'Bearer $token',
    };
    final text = rawBody ?? (body == null ? null : jsonEncode(body));
    return _Answer(
      await api.handle(
        ApiRequest(
          method: method,
          target: path,
          headers: all,
          body: text == null ? null : Uint8List.fromList(utf8.encode(text)),
        ),
      ),
    );
  }

  Future<String> signIn([String? as]) async {
    final answer = await call(
      'POST',
      Routes.signIn,
      body: {'email': as ?? email, 'password': testPassword},
    );
    return answer.body!['accessToken'] as String;
  }
}

_Server _aServer() => _Server(createHttpServerSide(InstalledFixtureServer()));

({Object body, Map<String, String> headers}) _voteRequest([Vote? vote]) {
  final cast = vote ?? aVote();
  return (
    body: toVoteRequestWire(cast).toJson(),
    headers: {
      HttpHeader.idempotencyKey.value: Uri.encodeComponent(cast.idempotencyKey),
    },
  );
}

Map<String, dynamic> _error(ApiErrorCode code) => {
  'error': {'code': code.value},
};

void main() {
  group('MockApi, the routes', () {
    for (final (method, path) in <(String, String)>[
      ('GET', '/'),
      ('GET', '/nowhere'),
      ('POST', '/meetings'),
      ('GET', '/votes'),
      ('PUT', '/votes'),
      ('DELETE', '/meetings/meeting-1'),
      ('GET', '/auth/sign-in'),
      ('GET', '/auth/other'),
      ('POST', '/documents/document-1/content'),
      ('GET', '/documents/document-1/other'),
      ('GET', '/meetings/meeting-1/extra'),
      ('GET', '/meetings/%E0%A4%A'),
    ]) {
      test('answers 404 and an error body for $method $path', () async {
        final server = _aServer();

        final answer = await server.call(method, path);

        expect(answer.status, equals(HttpStatusCode.notFound.code));
        expect(answer.body, equals(_error(ApiErrorCode.notFound)));
        expect(answer.contentType, equals('application/json'));
      });
    }
  });

  group('MockApi, what every answer says about being kept', () {
    test('asks that no answer be stored: a success, a refusal, '
        'a vote without a body and an unknown route', () async {
      final server = _aServer();
      final token = await server.signIn();

      final answers = [
        await server.call(
          'GET',
          '${Routes.meetings}?period=past&limit=5',
          token: token,
        ),
        await server.call('GET', '${Routes.meetings}?period=past&limit=5'),
        await server.call(
          'POST',
          Routes.votes,
          token: token,
          body: _voteRequest().body,
          headers: _voteRequest().headers,
        ),
        await server.call('GET', '/nowhere', token: token),
      ];

      expect(
        answers.map((answer) => answer.status),
        equals([
          HttpStatusCode.ok.code,
          HttpStatusCode.unauthorized.code,
          HttpStatusCode.noContent.code,
          HttpStatusCode.notFound.code,
        ]),
      );
      expect(
        answers.map((answer) => answer.cacheControl),
        equals(answers.map((answer) => 'no-store')),
      );
    });
  });

  group('MockApi, signing in', () {
    test('grants a token, a lifetime in seconds and the user, '
        'on the clock of the server', () async {
      final server = _aServer();

      final answer = await server.call(
        'POST',
        Routes.signIn,
        body: {'email': server.email, 'password': testPassword},
      );

      expect(answer.status, equals(HttpStatusCode.ok.code));
      expect(
        answer.body,
        equals({
          'accessToken': 'token-1',
          'tokenType': 'Bearer',
          'expiresIn': 3600,
          'user': {
            'id': 'user-1',
            'fullName': 'Alice Martin',
            'email': 'alice@example.com',
          },
        }),
      );
    });

    test('grants a new token at each sign-in', () async {
      final server = _aServer();

      expect([
        await server.signIn(),
        await server.signIn(),
      ], equals(['token-1', 'token-2']));
    });

    test(
      'takes the email as the domain reads it: trimmed, in lower case',
      () async {
        final server = _aServer();

        final answer = await server.call(
          'POST',
          Routes.signIn,
          body: {'email': '  ALICE@Example.com ', 'password': testPassword},
        );

        expect(answer.status, equals(HttpStatusCode.ok.code));
      },
    );

    for (final (name, body) in <(String, Map<String, Object?>)>[
      ('a wrong password', {'email': 'alice@example.com', 'password': 'nope'}),
      (
        'a password in another case',
        {'email': 'alice@example.com', 'password': testPassword.toUpperCase()},
      ),
      (
        'an unknown email',
        {'email': 'nobody@example.com', 'password': testPassword},
      ),
      (
        'an email that is not one',
        {'email': 'nobody', 'password': testPassword},
      ),
    ]) {
      test('answers 401 invalidCredentials for $name', () async {
        final server = _aServer();

        final answer = await server.call('POST', Routes.signIn, body: body);

        expect(answer.status, equals(HttpStatusCode.unauthorized.code));
        expect(answer.body, equals(_error(ApiErrorCode.invalidCredentials)));
      });
    }

    for (final (name, body, rawBody) in <(String, Object?, String?)>[
      ('text that is not JSON', null, 'not json'),
      ('no body', null, null),
      ('a body without a password', {'email': 'alice@example.com'}, null),
      (
        'a password that is a number',
        {'email': 'alice@example.com', 'password': 1},
        null,
      ),
    ]) {
      test('answers 400 for $name', () async {
        final server = _aServer();

        final answer = await server.call(
          'POST',
          Routes.signIn,
          body: body,
          rawBody: rawBody,
        );

        expect(answer.status, equals(HttpStatusCode.badRequest.code));
        expect(answer.body, equals(_error(ApiErrorCode.badRequest)));
      });
    }

    test('answers 503 when the simulated server is unreachable, '
        'before it looks at the credentials', () async {
      final server = _aServer();
      server.world.network.setOnline(online: false);

      final answer = await server.call(
        'POST',
        Routes.signIn,
        body: {'email': server.email, 'password': 'wrong'},
      );

      expect(answer.status, equals(HttpStatusCode.serviceUnavailable.code));
      expect(answer.body, equals(_error(ApiErrorCode.serviceUnavailable)));
    });

    test('writes a lifetime that is not whole seconds '
        'as the whole seconds it grants', () async {
      final world = createHttpServerSide(InstalledFixtureServer());
      final api = MockApi(
        MockApiOptions(
          backend: world.backend,
          clock: world.clock,
          accounts: world.accounts,
          sessionLifetime: aDuration(90500),
          generateToken: () => 'only-token',
        ),
      );

      final response = await api.handle(
        ApiRequest(
          method: 'POST',
          target: Routes.signIn,
          body: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'email': world.accounts.first.user.email,
                'password': testPassword,
              }),
            ),
          ),
        ),
      );

      expect(
        (jsonDecode(response.text) as Map<String, dynamic>)['expiresIn'],
        equals(90),
      );
    });
  });

  group('MockApi, authentication', () {
    for (final (name, token, headers)
        in <(String, String?, Map<String, String>)>[
          ('without an Authorization header', null, {}),
          (
            'with another scheme',
            null,
            {HttpHeader.authorization.value: 'Basic abc'},
          ),
          ('with an empty token', '', {}),
          ('with a token nobody was granted', 'invented', {}),
        ]) {
      test('answers 401 to a request $name', () async {
        final server = _aServer();

        final answer = await server.call(
          'GET',
          '${Routes.meetings}?period=upcoming&limit=5',
          token: token,
          headers: headers,
        );

        expect(answer.status, equals(HttpStatusCode.unauthorized.code));
        expect(answer.body, equals(_error(ApiErrorCode.unauthorized)));
      });
    }

    test(
      'answers 401 to every token once the server has forgotten them',
      () async {
        final server = _aServer();
        final token = await server.signIn();
        expect(
          (await server.call(
            'GET',
            Routes.meeting('meeting-1'),
            token: token,
          )).status,
          equals(HttpStatusCode.ok.code),
        );

        server.api.revokeSessions();

        expect(
          (await server.call(
            'GET',
            Routes.meeting('meeting-1'),
            token: token,
          )).status,
          equals(HttpStatusCode.unauthorized.code),
        );
      },
    );

    test('answers 401 once the lifetime it granted is over, '
        'on the clock of the server', () async {
      final server = _aServer();
      final token = await server.signIn();
      server.world.clock.advance(millisPerHour - 1);
      expect(
        (await server.call(
          'GET',
          Routes.meeting('meeting-1'),
          token: token,
        )).status,
        equals(HttpStatusCode.ok.code),
      );

      server.world.clock.advance(1);

      expect(
        (await server.call(
          'GET',
          Routes.meeting('meeting-1'),
          token: token,
        )).status,
        equals(HttpStatusCode.unauthorized.code),
      );
    });

    test('answers each request for the user its token belongs to', () async {
      final server = _aServer();
      final bruno = server.world.accounts[1].user.email;
      final alice = await server.signIn();
      final other = await server.signIn(bruno);

      final asAlice = await server.call(
        'GET',
        Routes.meeting('meeting-1'),
        token: alice,
      );
      final asBruno = await server.call(
        'GET',
        Routes.meeting('meeting-1'),
        token: other,
      );

      final resolution =
          ((asAlice.body!['agenda'] as List<dynamic>)[1]
                  as Map<String, dynamic>)['resolution']
              as Map<String, dynamic>;
      expect(resolution, isNot(contains('recordedVote')));
      expect(asBruno.status, equals(HttpStatusCode.ok.code));
    });
  });

  group('MockApi, reading', () {
    test('lists a page of summaries for a period, '
        'with a limit and a cursor', () async {
      final server = _aServer();
      server.world.load(
        ServerContent(
          meetings: [
            for (final day in [1, 2, 3])
              aMeetingWithAgenda().copyWith(
                id: aMeetingId('m-$day'),
                agenda: [],
                scheduledAt: after(
                  aMeetingWithAgenda().scheduledAt,
                  day * 1000,
                ),
              ),
          ],
          recordedVotes: const [],
        ),
      );
      final token = await server.signIn();

      final first = await server.call(
        'GET',
        '${Routes.meetings}?period=upcoming&limit=2',
        token: token,
      );
      final nextCursor = first.body!['nextCursor'] as String;
      final second = await server.call(
        'GET',
        '${Routes.meetings}?period=upcoming&limit=2'
            '&cursor=${Uri.encodeComponent(nextCursor)}',
        token: token,
      );

      List<String> ids(_Answer answer) => [
        for (final item in answer.body!['items'] as List<dynamic>)
          (item as Map<String, dynamic>)['id'] as String,
      ];
      expect(first.status, equals(HttpStatusCode.ok.code));
      expect(ids(first), equals(['m-1', 'm-2']));
      expect(
        ((first.body!['items'] as List<dynamic>).first as Map<String, dynamic>)
            .keys,
        equals(['id', 'title', 'scheduledAt', 'location']),
      );
      expect(ids(second), equals(['m-3']));
      expect(second.body, isNot(contains('nextCursor')));
    });

    for (final (name, query) in <(String, String)>[
      ('no period', 'limit=5'),
      ('a period nobody knows', 'period=someday&limit=5'),
      ('no limit', 'period=past'),
      ('a limit of zero', 'period=past&limit=0'),
      ('a limit above the maximum', 'period=past&limit=51'),
      ('a limit that is text', 'period=past&limit=ten'),
      ('a limit that is empty', 'period=past&limit='),
      ('a limit that is not whole', 'period=past&limit=2.5'),
      ('a limit in exponent notation', 'period=past&limit=1e1'),
      ('a limit with a space', 'period=past&limit=%2010'),
      ('a limit with a trailing space', 'period=past&limit=10%20'),
      ('a limit in hexadecimal', 'period=past&limit=0x10'),
      ('a limit in binary', 'period=past&limit=0b11'),
      ('a limit with a sign', 'period=past&limit=%2B5'),
      ('a limit with a leading zero', 'period=past&limit=05'),
      ('a limit with a decimal comma', 'period=past&limit=2,5'),
      ('a cursor that is blank', 'period=past&limit=5&cursor=%20'),
      (
        'a cursor this server did not write',
        'period=past&limit=5&cursor=garbage',
      ),
    ]) {
      test('answers 400 for $name', () async {
        final server = _aServer();
        final token = await server.signIn();

        final answer = await server.call(
          'GET',
          '${Routes.meetings}?$query',
          token: token,
        );

        expect(answer.status, equals(HttpStatusCode.badRequest.code));
        expect(answer.body, equals(_error(ApiErrorCode.badRequest)));
      });
    }

    test(
      'answers 503 for a listing when the simulated server is unreachable',
      () async {
        final server = _aServer();
        final token = await server.signIn();
        server.world.network.setOnline(online: false);

        final answer = await server.call(
          'GET',
          '${Routes.meetings}?period=past&limit=5',
          token: token,
        );

        expect(answer.status, equals(HttpStatusCode.serviceUnavailable.code));
      },
    );

    test(
      'answers a meeting with its agenda, documents and participants',
      () async {
        final server = _aServer();
        final token = await server.signIn();

        final answer = await server.call(
          'GET',
          Routes.meeting('meeting-1'),
          token: token,
        );

        expect(answer.status, equals(HttpStatusCode.ok.code));
        expect(
          answer.body!.keys.toList()..sort(),
          equals(
            [
              'agenda',
              'documents',
              'id',
              'location',
              'participants',
              'scheduledAt',
              'title',
            ]..sort(),
          ),
        );
      },
    );

    test('answers 404 for a meeting that does not exist '
        'and 403 for one the user is not invited to', () async {
      final server = _aServer();
      server.world.load(
        ServerContent(
          meetings: [
            aMeetingWithAgenda(
              participants: aMeetingWithAgenda().participants.sublist(1),
            ),
          ],
          recordedVotes: const [],
        ),
      );
      final token = await server.signIn();

      expect(
        (await server.call(
          'GET',
          Routes.meeting('nowhere'),
          token: token,
        )).status,
        equals(HttpStatusCode.notFound.code),
      );
      final forbidden = await server.call(
        'GET',
        Routes.meeting('meeting-1'),
        token: token,
      );
      expect(forbidden.status, equals(HttpStatusCode.forbidden.code));
      expect(forbidden.body, equals(_error(ApiErrorCode.forbidden)));
    });

    test(
      'answers 404, not 400, for an id the domain does not accept',
      () async {
        final server = _aServer();
        final token = await server.signIn();

        expect(
          (await server.call(
            'GET',
            Routes.meeting('%20'),
            token: token,
          )).status,
          equals(HttpStatusCode.notFound.code),
        );
        expect(
          (await server.call(
            'GET',
            Routes.document('x' * 200),
            token: token,
          )).status,
          equals(HttpStatusCode.notFound.code),
        );
        expect(
          (await server.call(
            'GET',
            Routes.documentContent(' '),
            token: token,
          )).status,
          equals(HttpStatusCode.notFound.code),
        );
      },
    );

    test('reads an id that is percent-encoded', () async {
      final server = _aServer();
      server.world.load(
        ServerContent(
          meetings: [aMeetingWithAgenda().copyWith(id: aMeetingId('a/b c'))],
          recordedVotes: const [],
        ),
      );
      final token = await server.signIn();

      final answer = await server.call(
        'GET',
        Routes.meeting('a/b c'),
        token: token,
      );

      expect(answer.status, equals(HttpStatusCode.ok.code));
      expect(answer.body!['id'], equals('a/b c'));
    });

    test('answers a document', () async {
      final server = _aServer();
      final token = await server.signIn();

      final document = await server.call(
        'GET',
        Routes.document('document-1'),
        token: token,
      );

      expect(
        document.body,
        equals({
          'id': 'document-1',
          'title': 'Financial statements',
          'confidentiality': 'confidential',
          'pageCount': 3,
        }),
      );
    });

    group('the content of a document', () {
      test('is the file itself, as application/pdf, '
          'with one page for each page of the document', () async {
        final server = _aServer();
        final token = await server.signIn();

        final content = await server.call(
          'GET',
          Routes.documentContent('document-1'),
          token: token,
        );

        expect(content.status, equals(HttpStatusCode.ok.code));
        expect(content.contentType, equals('application/pdf'));
        expect(hasPdfSignature(content.bytes), isTrue);
        expect(content.text, contains('/Count 3'));
        expect(content.text, contains('(Financial statements) Tj'));
      });

      test('is not to be stored by anything between the server and the app, '
          'and carries the version as its ETag', () async {
        final server = _aServer();
        final token = await server.signIn();

        final content = await server.call(
          'GET',
          Routes.documentContent('document-1'),
          token: token,
        );

        expect(content.cacheControl, equals('no-store'));
        expect(content.etag, matches(RegExp(r'^"[^"]+"$')));
      });

      test('has the same version while the content of the server is the same, '
          'and another once it changed', () async {
        final server = _aServer();
        final token = await server.signIn();
        final first = await server.call(
          'GET',
          Routes.documentContent('document-1'),
          token: token,
        );
        final again = await server.call(
          'GET',
          Routes.documentContent('document-1'),
          token: token,
        );

        server.world.load(
          ServerContent(
            meetings: [aMeetingWithAgenda()],
            recordedVotes: const [],
          ),
        );
        final replaced = await server.call(
          'GET',
          Routes.documentContent('document-1'),
          token: token,
        );

        expect(again.etag, equals(first.etag));
        expect(replaced.etag, isNot(equals(first.etag)));
      });

      test('is refused without a token, like the metadata', () async {
        final server = _aServer();

        final content = await server.call(
          'GET',
          Routes.documentContent('document-1'),
        );

        expect(content.status, equals(HttpStatusCode.unauthorized.code));
        expect(content.body, equals(_error(ApiErrorCode.unauthorized)));
        expect(content.contentType, equals('application/json'));
      });

      test('is refused for a document that does not exist', () async {
        final server = _aServer();
        final token = await server.signIn();

        final content = await server.call(
          'GET',
          Routes.documentContent('nowhere'),
          token: token,
        );

        expect(content.status, equals(HttpStatusCode.notFound.code));
        expect(content.body, equals(_error(ApiErrorCode.notFound)));
      });

      test('is refused while the simulated network is cut', () async {
        final server = _aServer();
        final token = await server.signIn();
        server.world.network.setOnline(online: false);

        final content = await server.call(
          'GET',
          Routes.documentContent('document-1'),
          token: token,
        );

        expect(content.status, equals(HttpStatusCode.serviceUnavailable.code));
      });
    });

    test('answers 404 and 403 for documents like for meetings', () async {
      final server = _aServer();
      server.world.load(
        ServerContent(
          meetings: [
            aMeetingWithAgenda(
              participants: aMeetingWithAgenda().participants.sublist(1),
            ),
          ],
          recordedVotes: const [],
        ),
      );
      final token = await server.signIn();

      expect(
        (await server.call(
          'GET',
          Routes.document('nowhere'),
          token: token,
        )).status,
        equals(HttpStatusCode.notFound.code),
      );
      expect(
        (await server.call(
          'GET',
          Routes.document('document-1'),
          token: token,
        )).status,
        equals(HttpStatusCode.forbidden.code),
      );
      expect(
        (await server.call(
          'GET',
          Routes.documentContent('document-1'),
          token: token,
        )).status,
        equals(HttpStatusCode.forbidden.code),
      );
    });
  });

  group('MockApi, casting a vote', () {
    test(
      'records a vote and answers 204 with no body, again for the same vote, '
      'and 422 for another choice',
      () async {
        final server = _aServer();
        final token = await server.signIn();

        Future<_Answer> cast(Vote vote) async {
          final request = _voteRequest(vote);
          return await server.call(
            'POST',
            Routes.votes,
            token: token,
            body: request.body,
            headers: request.headers,
          );
        }

        final first = await cast(aVote());
        final again = await cast(aVote(castAt: after(aVote().castAt, 5)));
        final other = await cast(aVote(choice: VoteChoice.against));

        expect(first.status, equals(HttpStatusCode.noContent.code));
        expect(first.text, equals(''));
        expect(again.status, equals(HttpStatusCode.noContent.code));
        expect(other.status, equals(HttpStatusCode.unprocessableContent.code));
        expect(
          other.body,
          equals({
            'error': {
              'code': VotingErrorCode.alreadyVoted.value,
              'source': 'recorded',
            },
          }),
        );
        expect(server.world.backend.recordedVotes(), hasLength(1));
      },
    );

    test(
      'answers 422 with the rule that refused it, for each business rule',
      () async {
        final server = _aServer();
        final token = await server.signIn();
        final request = _voteRequest(
          aVote(resolutionId: aResolutionId('nowhere')),
        );

        final unknown = await server.call(
          'POST',
          Routes.votes,
          token: token,
          body: request.body,
          headers: request.headers,
        );

        expect(
          unknown.status,
          equals(HttpStatusCode.unprocessableContent.code),
        );
        expect(
          unknown.body,
          equals({
            'error': {
              'code': VotingErrorCode.resolutionNotFound.value,
              'resolutionId': 'nowhere',
            },
          }),
        );
      },
    );

    test('answers 401 to a vote whose voter is not the user of the token, '
        'and records nothing', () async {
      final server = _aServer();
      final token = await server.signIn();
      final request = _voteRequest(aVote(voterId: aUserId('user-2')));

      final answer = await server.call(
        'POST',
        Routes.votes,
        token: token,
        body: request.body,
        headers: request.headers,
      );

      expect(answer.status, equals(HttpStatusCode.unauthorized.code));
      expect(server.world.backend.recordedVotes(), isEmpty);
    });

    for (final (name, body, rawBody, headers)
        in <(String, Object?, String?, Map<String, String>?)>[
          ('text that is not JSON', null, 'nope', null),
          ('a body that is not a vote', {'choice': 'for'}, null, null),
          (
            'a choice nobody knows',
            {...toVoteRequestWire(aVote()).toJson(), 'choice': 'maybe'},
            null,
            null,
          ),
          (
            'a missing idempotency key',
            toVoteRequestWire(aVote()).toJson(),
            null,
            null,
          ),
          (
            'an idempotency key that is not the one of the vote',
            toVoteRequestWire(aVote()).toJson(),
            null,
            {HttpHeader.idempotencyKey.value: 'forged'},
          ),
          (
            'an idempotency key that is malformed',
            toVoteRequestWire(aVote()).toJson(),
            null,
            {HttpHeader.idempotencyKey.value: '%E0%A4%A'},
          ),
        ]) {
      test('answers 400 for $name', () async {
        final server = _aServer();
        final token = await server.signIn();

        final answer = await server.call(
          'POST',
          Routes.votes,
          token: token,
          body: body,
          rawBody: rawBody,
          headers: headers ?? const {},
        );

        expect(answer.status, equals(HttpStatusCode.badRequest.code));
        expect(server.world.backend.recordedVotes(), isEmpty);
      });
    }

    test(
      'reads the key of the vote in a header that is percent-encoded',
      () async {
        final server = _aServer();
        server.world.load(
          ServerContent(
            meetings: [aMeetingWithAgenda()],
            recordedVotes: const [],
          ),
        );
        final token = await server.signIn();
        final vote = aVote();

        final answer = await server.call(
          'POST',
          Routes.votes,
          token: token,
          body: toVoteRequestWire(vote).toJson(),
          headers: {
            HttpHeader.idempotencyKey.value: Uri.encodeComponent(
              vote.idempotencyKey,
            ),
          },
        );

        expect(vote.idempotencyKey, equals('12.resolution-1.user-1'));
        expect(answer.status, equals(HttpStatusCode.noContent.code));
      },
    );

    test('answers 503 when the simulated server is unreachable, '
        'and records nothing', () async {
      final server = _aServer();
      final token = await server.signIn();
      server.world.network.setOnline(online: false);
      final request = _voteRequest();

      final answer = await server.call(
        'POST',
        Routes.votes,
        token: token,
        body: request.body,
        headers: request.headers,
      );

      expect(answer.status, equals(HttpStatusCode.serviceUnavailable.code));
      expect(server.world.backend.recordedVotes(), isEmpty);
    });
  });

  group('MockApi, in Dart', () {
    test('reads a query as a URL query: + is a space, a malformed escape '
        'stays as written', () async {
      final server = _aServer();
      final token = await server.signIn();

      final plus = await server.call(
        'GET',
        '${Routes.meetings}?period=past&limit=+5',
        token: token,
      );
      final malformed = await server.call(
        'GET',
        '${Routes.meetings}?period=past&limit=5&cursor=%E0%A4%A',
        token: token,
      );

      expect(plus.status, equals(HttpStatusCode.badRequest.code));
      expect(malformed.status, equals(HttpStatusCode.badRequest.code));
    });

    test('takes the first value of a parameter that is repeated', () async {
      final server = _aServer();
      final token = await server.signIn();

      final answer = await server.call(
        'GET',
        '${Routes.meetings}?period=past&limit=5&limit=0',
        token: token,
      );

      expect(answer.status, equals(HttpStatusCode.ok.code));
    });

    test('knows the method whatever its case', () async {
      final server = _aServer();
      final token = await server.signIn();

      final answer = await server.call(
        'get',
        '${Routes.meetings}?period=past&limit=5',
        token: token,
      );

      expect(answer.status, equals(HttpStatusCode.ok.code));
    });

    test('finds the Authorization header whatever its case', () async {
      final server = _aServer();
      final token = await server.signIn();

      final answer = await server.call(
        'GET',
        '${Routes.meetings}?period=past&limit=5',
        headers: {'authorization': 'Bearer $token'},
      );

      expect(answer.status, equals(HttpStatusCode.ok.code));
    });

    test('has the codes of docs/api.md for the bodies of its errors', () {
      expect(
        ApiErrorCode.values.map((code) => code.value),
        equals([
          'badRequest',
          'invalidCredentials',
          'unauthorized',
          'forbidden',
          'notFound',
          'serviceUnavailable',
          'unexpected',
        ]),
      );
    });
  });
}
