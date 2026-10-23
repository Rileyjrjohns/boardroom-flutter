import 'dart:convert';

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/http/protocol.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/infrastructure/http_adapters_world.dart';
import '../../../support/infrastructure/http_world.dart';

// What the contract suite of VoteRepository does not say about the HTTP
// adapter: what it sends, and what it makes of a rejection. React Native has no
// test file for the repository; its contract suite and HttpAdapterGuards go
// through it.

void main() {
  final installed = installFixtureServer();

  /// The server sends [body] with the [status], whatever the request.
  void serverSends(int status, Object body) {
    installed.answerWith = (_) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        HttpHeader.contentType.value: [mediaTypeJson],
      },
    );
  }

  group('HttpVoteRepository, what it sends', () {
    test('posts the vote to the votes route, as JSON, with its key in a '
        'header and the token of the voter', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      installed.received.clear();
      installed.receivedHeaders.clear();
      final vote = aVote();

      await world.votes.submit(vote);

      expect(installed.received, equals(['POST $testApiUrl${Routes.votes}']));
      expect(
        installed.receivedHeader(0, HttpHeader.idempotencyKey.value),
        equals(Uri.encodeComponent(vote.idempotencyKey)),
      );
      expect(
        installed.receivedHeader(0, HttpHeader.contentType.value),
        contains(mediaTypeJson),
      );
      expect(
        installed.receivedHeader(0, HttpHeader.authorization.value),
        startsWith('Bearer token-'),
      );
    });
  });

  group('HttpVoteRepository, a rejection of the server', () {
    for (final (name, body, expected)
        in <(String, Map<String, Object>, VotingError)>[
          (
            'a resolution that is closed',
            {'code': 'resolutionClosed'},
            const ResolutionClosedError(),
          ),
          (
            'a voting window that is over',
            {'code': 'votingWindowOver'},
            const VotingWindowOverError(),
          ),
          (
            'a voter who is not a participant',
            {'code': 'notAParticipant'},
            const NotAParticipantError(),
          ),
          (
            'a voter with no voting rights',
            {'code': 'noVotingRights'},
            const NoVotingRightsError(),
          ),
          (
            'a vote already recorded',
            {'code': 'alreadyVoted', 'source': 'recorded'},
            const AlreadyVotedError(source: AlreadyVotedSource.recorded),
          ),
          (
            'a resolution the meeting does not have',
            {'code': 'resolutionNotFound', 'resolutionId': 'resolution-9'},
            ResolutionNotFoundError(
              resolutionId: aResolutionId('resolution-9'),
            ),
          ),
        ]) {
      test('is the voting error for $name', () async {
        final world = createHttpWorld(installed);
        await world.signInAs(aUserId());
        serverSends(422, {'error': body});

        expect(await world.votes.submit(aVote()), equals(err(expected)));
      });
    }

    test('is unexpected, and the monitoring is told where it broke the '
        'schema, when the description is not one of a voting error', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      serverSends(422, {
        'error': {'code': 'somethingElse'},
      });

      expect(
        await world.votes.submit(aVote()),
        equals(err(unexpected('invalid response'))),
      );
      expect(
        world.monitoring.errors.single.attributes,
        equals({
          LogAttribute.resource: 'vote',
          LogAttribute.issuePaths: 'code',
        }),
      );
    });

    test('is unexpected, and the monitoring is told the rule, when the '
        'description breaks a rule of the domain', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      serverSends(422, {
        'error': {'code': 'resolutionNotFound', 'resolutionId': '  '},
      });

      expect(
        await world.votes.submit(aVote()),
        equals(err(unexpected('invalid response'))),
      );
      expect(
        world.monitoring.errors.single.error,
        isA<ValidationError>().having(
          (error) => error.field,
          'field',
          ValidationField.resolutionId,
        ),
      );
      expect(
        world.monitoring.capturedEvents(),
        equals([MonitoringEvent.responseInvalid]),
      );
    });

    test(
      'is unexpected, with the status, for a 422 with no description',
      () async {
        final world = createHttpWorld(installed);
        await world.signInAs(aUserId());
        installed.answerWith = (_) => ResponseBody.fromString('', 422);

        expect(
          await world.votes.submit(aVote()),
          equals(err(unexpected('status 422'))),
        );
      },
    );

    for (final (status, expected) in <(int, GatewayError)>[
      (403, unexpected('status 403')),
      (404, unexpected('status 404')),
      (500, unexpected('status 500')),
      (503, networkUnavailable()),
    ]) {
      test('is a gateway error for the status $status', () async {
        final world = createHttpWorld(installed);
        await world.signInAs(aUserId());
        installed.answerWith = (_) => ResponseBody.fromString('', status);

        expect(await world.votes.submit(aVote()), equals(err(expected)));
      });
    }
  });
}
