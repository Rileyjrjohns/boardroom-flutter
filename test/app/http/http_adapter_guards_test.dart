import 'dart:convert';
import 'dart:typed_data';

import 'package:boardroom/app/dev/fixture_server/api_message.dart';
import 'package:boardroom/app/dev/fixture_server/mock_api.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/page_cursor.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/core/infrastructure/http/http_client.dart';
import 'package:boardroom/core/infrastructure/http/protocol.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:boardroom/features/votes/infrastructure/dto/vote_dto.dart';
import 'package:boardroom/features/votes/infrastructure/http_vote_repository.dart';
import 'package:test/test.dart';

import '../../support/builders/builders.dart';
import '../../support/fakes/fake_clock.dart';
import '../../support/fakes/fake_monitoring.dart';
import '../../support/infrastructure/http_adapters_world.dart';
import '../../support/infrastructure/http_world.dart';
import '../../support/infrastructure/scripted_adapter.dart';
import '../../support/infrastructure/test_server.dart';

// The HTTP adapters promise never to throw or reject, whatever they are given.
// The identifiers and the cursor are checked by the domain, but an adapter does
// not rely on it: a value that cannot be put in an address (a lone surrogate,
// which `encodeURIComponent` refuses) is a failure, never an exception, and
// nothing is sent.

/// Text that cannot be percent-encoded.
const String _loneSurrogate = '\uD800';

const String _causeNotBuilt = 'request could not be built';

const String _baseUrl = 'http://api.boardroom.test';

final Result<Never, RepositoryError> _notBuilt = err(
  unexpected(_causeNotBuilt),
);

/// A repository of votes over a client whose adapter answers [answer], for the
/// user [voter], and what the adapter was sent.
({HttpVoteRepository votes, ScriptedAdapter adapter}) _votesAnswered(
  ScriptedAnswer answer, {
  UserId? voter,
}) {
  final adapter = ScriptedAdapter([answer]);
  final monitoring = FakeMonitoring();
  final client = HttpClient(
    HttpClientOptions(
      baseUrl: _baseUrl,
      timeout: aDuration(1000),
      tokens: _Tokens(voter ?? aUserId()),
      monitoring: monitoring,
      adapter: adapter,
    ),
  );
  return (votes: HttpVoteRepository(client, monitoring), adapter: adapter);
}

final class _Tokens implements BearerTokenSource {
  const new(this._userId);

  final UserId _userId;

  @override
  Future<Result<BearerToken?, StorageReadFailedError>> token() =>
      Future.value(ok(BearerToken(token: 't', userId: _userId)));
}

void main() {
  final installed = installFixtureServer();

  group('The HTTP adapters, given what cannot be put in an address', () {
    test('answer unexpected, without sending anything, for a meeting that '
        'cannot be addressed', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      installed.received.clear();

      final answer = await world.meetings.get(_loneSurrogate as MeetingId);

      expect(answer, equals(_notBuilt));
      expect(installed.received, isEmpty);
    });

    test('answer unexpected for a document and for its content that cannot '
        'be addressed', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      installed.received.clear();

      final document = await world.documents.get(_loneSurrogate as DocumentId);
      final content = await world.documents.fetchContent(
        _loneSurrogate as DocumentId,
      );

      expect(document, equals(_notBuilt));
      expect(content, equals(_notBuilt));
      expect(installed.received, isEmpty);
    });

    test('answer unexpected for a page whose cursor cannot be put in the '
        'query', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      installed.received.clear();
      // The domain refuses such a cursor: this is a value that got past it.
      const request = PageRequest(
        limit: 10,
        cursor: _loneSurrogate as PageCursor,
      );

      final answer = await world.meetings.list(MeetingPeriod.upcoming, request);

      expect(answer, equals(_notBuilt));
      expect(installed.received, isEmpty);
    });

    test('answer unexpected for a vote whose idempotency key cannot be put '
        'in a header', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      installed.received.clear();
      final vote = aVote().copyWith(
        idempotencyKey: _loneSurrogate as IdempotencyKey,
      );

      final answer = await world.votes.submit(vote);

      expect(answer, equals(_notBuilt));
      expect(installed.received, isEmpty);
    });

    test('do not leak the value they were given', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());

      final answer = await world.meetings.get(_loneSurrogate as MeetingId);

      expect('$answer', isNot(contains('uD800')));
      expect('$answer', isNot(contains(_loneSurrogate)));
    });
  });

  group('HttpVoteRepository, a vote of a user who is no longer the '
      'signed-in one', () {
    test('is not sent: the voter must be the user the token belongs '
        'to', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      // Alice's vote is ready to go; then somebody else signs in on the
      // device.
      final alices = aVote();
      await world.signInAs(aUserId('user-2'));
      installed.received.clear();

      final answer = await world.votes.submit(alices);

      expect(answer, equals(err(unauthorized())));
      expect(installed.received, isEmpty);
    });

    test('is sent when the voter is the signed-in user', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      installed.received.clear();

      await world.votes.submit(aVote());

      expect(installed.received, hasLength(1));
    });
  });

  group('HttpVoteRepository, a success whose body is not JSON', () {
    test('is a success: the vote was recorded, whatever the body '
        'says', () async {
      final scripted = _votesAnswered(
        const ScriptedAnswer(status: 201, text: '<html>created</html>'),
      );

      expect(await scripted.votes.submit(aVote()), equals(ok<void>(null)));
    });

    test('is a success without reading the body at all', () async {
      final scripted = _votesAnswered(
        const ScriptedAnswer(
          status: 204,
          text: 'must not be read',
          paced: true,
        ),
      );

      expect(await scripted.votes.submit(aVote()), equals(ok<void>(null)));
      expect(scripted.adapter.reading.chunksRead, equals(0));
    });
  });

  group('HttpVoteRepository, the idempotency key in a header', () {
    // Ids with every kind of character that is not safe in a header or a path.
    const awkward = [
      ('spaces and a slash', 'résolution 1/a', 'utilisateur 1'),
      ('a percent sign and a colon', '100%:ok', 'u%41:1'),
      ('a line break and a quote', 'r\r\nX-Injected: yes', 'u"1\''),
      ('letters outside ASCII', '決議1', 'ユーザー1'),
      ('an emoji, which is two code units', 'r\u{1F5F3}', 'u\u{1F464}'),
    ];

    Future<
      ({Vote vote, Result<void, Object?> answer, Map<String, String> headers})
    >
    sentHeaders(String resolution, String voter) async {
      final vote = aVote(
        resolutionId: aResolutionId(resolution),
        voterId: aUserId(voter),
      );
      final scripted = _votesAnswered(
        const ScriptedAnswer(status: 204),
        voter: aUserId(voter),
      );
      final answer = await scripted.votes.submit(vote);
      return (
        vote: vote,
        answer: answer,
        headers: {
          for (final entry
              in scripted.adapter.sent.single.options.headers.entries)
            entry.key: '${entry.value}',
        },
      );
    }

    for (final (name, resolution, voter) in awkward) {
      test('sends the key as ASCII that gives it back, for $name', () async {
        final (:vote, :answer, :headers) = await sentHeaders(resolution, voter);

        final key = headers[HttpHeader.idempotencyKey.value];
        expect(answer, equals(ok<void>(null)));
        expect(key, equals(Uri.encodeComponent(vote.idempotencyKey)));
        expect(key, matches(RegExp(r'^[\x21-\x7E]+$')));
        expect(Uri.decodeComponent(key ?? ''), equals(vote.idempotencyKey));
      });
    }

    for (final (name, resolution, voter) in awkward) {
      test('is accepted by the server as the key of the vote, for '
          '$name', () async {
        final (:vote, answer: _, :headers) = await sentHeaders(
          resolution,
          voter,
        );
        final api = MockApi(
          MockApiOptions(
            backend: createTestServer(const TestServerOptions(signedIn: false))
                .backend,
            clock: FakeClock(),
            accounts: const [],
            sessionLifetime: aDuration(1000),
            generateToken: () => 't',
          ),
        );

        final answer = await api.handle(
          ApiRequest(
            method: HttpMethod.post.value,
            target: Routes.votes,
            headers: {...headers, HttpHeader.contentType.value: mediaTypeJson},
            body: Uint8List.fromList(
              utf8.encode(jsonEncode(toVoteRequestWire(vote).toJson())),
            ),
          ),
        );

        // The key and the body agree: the request is refused for who sent it,
        // not for being malformed.
        expect(answer.status, equals(HttpStatusCode.unauthorized.code));
      });
    }
  });
}
