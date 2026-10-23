import 'dart:async';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/ports/vote_repository.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:test/test.dart';

import '../builders/builders.dart';

/// What the suite needs to test a vote repository. Before the suite starts, the
/// server holds `aMeetingWithAgenda()` (meeting `meeting-1`, whose resolutions
/// are `resolution-1` and `resolution-2`, both open, and where `user-1` is a
/// member) and the requests are authenticated as `user-1`.
final class VoteRepositoryHarness {
  /// Creates a harness.
  const new({
    required this.repository,
    required this.now,
    required this.setOnline,
    required this.signOut,
    required this.authenticateAs,
    required this.serve,
    required this.change,
    required this.advanceClock,
    required this.recordedCount,
  });

  /// The adapter under test.
  final VoteRepository repository;

  /// The instant the server takes for the present.
  final Instant now;

  /// Cuts and restores the connection.
  final void Function({required bool online}) setOnline;

  /// Nobody is authenticated any more.
  final FutureOr<void> Function() signOut;

  /// From now on the requests are authenticated as this user.
  final FutureOr<void> Function(UserId userId) authenticateAs;

  /// Makes the server hold exactly this meeting, and nothing recorded. For the
  /// business rules.
  final FutureOr<void> Function(Meeting meeting) serve;

  /// Replaces the meeting on the server, and keeps the votes that were
  /// recorded.
  final FutureOr<void> Function(Meeting meeting) change;

  /// Moves the clock of the server forward, by less than the life of a session.
  /// The server stamps a vote with its own time, so this is how a test lets a
  /// voting window end.
  final void Function(int millis) advanceClock;

  /// How many votes the server recorded under the key of this vote.
  final FutureOr<int> Function(Vote vote) recordedCount;
}

/// Makes a harness, now or later.
typedef VoteRepositoryFactory = FutureOr<VoteRepositoryHarness> Function();

/// What an implementation of the repository can be asked beyond what any can.
final class VoteRepositoryContractOptions {
  /// Creates the options.
  const new({required this.enforcesBusinessRules});

  /// Whether the server applies the business rules of a vote (closed, not
  /// eligible, ...), which means it holds the meetings. The scripted server of
  /// the fakes does not.
  final bool enforcesBusinessRules;
}

final UserId _secretary = aUserId('user-3');
final UserId _outsider = aUserId('user-9');

/// The contract of `VoteRepository`, as a suite any implementation runs:
/// idempotent on the idempotency key, a second choice under the same key is
/// `alreadyVoted`, a vote is only recorded for the user the request is
/// authenticated as (`unauthorized` otherwise), failures are results. With
/// `enforcesBusinessRules`, also the business rejections.
void describeVoteRepositoryContract(
  String name,
  VoteRepositoryFactory createHarness,
  VoteRepositoryContractOptions options,
) {
  group('$name honours the VoteRepository contract', () {
    late VoteRepositoryHarness harness;
    late VoteRepository repository;

    setUp(() async {
      harness = await createHarness();
      repository = harness.repository;
    });

    test('records a vote', () async {
      expect(await repository.submit(aVote()), equals(ok<void>(null)));
      expect(await harness.recordedCount(aVote()), equals(1));
    });

    test('is idempotent on the key: the same vote sent twice '
        'is recorded once, and succeeds both times', () async {
      expect(await repository.submit(aVote()), equals(ok<void>(null)));
      expect(await repository.submit(aVote()), equals(ok<void>(null)));
      expect(
        await repository.submit(aVote(castAt: at(5000))),
        equals(ok<void>(null)),
      );

      expect(await harness.recordedCount(aVote()), equals(1));
    });

    test('rejects another choice under the same key as already voted, '
        'and keeps the first', () async {
      await repository.submit(aVote());

      expect(
        await repository.submit(aVote(choice: VoteChoice.against)),
        equals(
          err(const AlreadyVotedError(source: AlreadyVotedSource.recorded)),
        ),
      );
      expect(await harness.recordedCount(aVote()), equals(1));
      expect(await repository.submit(aVote()), equals(ok<void>(null)));
    });

    test('records one vote per resolution', () async {
      final second = aVote(resolutionId: aResolutionId('resolution-2'));

      expect(await repository.submit(aVote()), equals(ok<void>(null)));
      expect(await repository.submit(second), equals(ok<void>(null)));

      expect(await harness.recordedCount(aVote()), equals(1));
      expect(await harness.recordedCount(second), equals(1));
    });

    group('only records a vote for the user '
        'the request is authenticated as', () {
      test('answers unauthorized, not a voting error, '
          'to the vote of somebody else', () async {
        final theirs = aVote(voterId: aUserId('user-2'));

        expect(await repository.submit(theirs), equals(err(unauthorized())));
        expect(await harness.recordedCount(theirs), equals(0));
      });

      test('answers unauthorized when nobody is authenticated', () async {
        await harness.signOut();

        expect(await repository.submit(aVote()), equals(err(unauthorized())));
        expect(await harness.recordedCount(aVote()), equals(0));
      });
    });

    group('failures are results', () {
      test('answers networkUnavailable without a connection, '
          'records nothing, and recovers', () async {
        harness.setOnline(online: false);

        expect(
          await repository.submit(aVote()),
          equals(err(networkUnavailable())),
        );
        expect(await harness.recordedCount(aVote()), equals(0));

        harness.setOnline(online: true);
        expect(await repository.submit(aVote()), equals(ok<void>(null)));
        expect(await harness.recordedCount(aVote()), equals(1));
      });
    });

    // A server that only replays scripted answers (the fakes) skips these: they
    // show as skipped.
    group('business rules', () {
      /// A meeting whose only resolution is `resolution`, with the standard
      /// participants.
      Meeting meetingWith(Resolution resolution) =>
          aMeeting(agenda: [anAgendaItem(resolution: resolution)]);

      group('a vote that the server already holds under the key', () {
        const otherChoice = VoteChoice.against;
        const halfAnHour = 30 * millisPerMinute;
        Meeting closingIn(int millis) => meetingWith(
          aResolution(closesAt: unwrap(parseInstant(harness.now + millis))),
        );

        test('answers alreadyVoted to another choice '
            'once the voting window is over', () async {
          await harness.serve(closingIn(halfAnHour));
          await repository.submit(aVote());
          harness.advanceClock(halfAnHour + 1);

          expect(
            await repository.submit(aVote(choice: otherChoice)),
            equals(
              err(const AlreadyVotedError(source: AlreadyVotedSource.recorded)),
            ),
          );
        });

        test('answers success to the same choice once the voting window '
            'is over, and records nothing more', () async {
          await harness.serve(closingIn(halfAnHour));
          await repository.submit(aVote());
          harness.advanceClock(halfAnHour + 1);

          expect(await repository.submit(aVote()), equals(ok<void>(null)));
          expect(await harness.recordedCount(aVote()), equals(1));
        });

        test('answers alreadyVoted to another choice '
            'once the resolution is closed', () async {
          await harness.serve(meetingWith(aResolution()));
          await repository.submit(aVote());
          await harness.change(
            meetingWith(aResolution(status: ResolutionStatus.closed)),
          );

          expect(
            await repository.submit(aVote(choice: otherChoice)),
            equals(
              err(const AlreadyVotedError(source: AlreadyVotedSource.recorded)),
            ),
          );
        });

        test('answers success to the same choice once the resolution '
            'is closed, and records nothing more', () async {
          await harness.serve(meetingWith(aResolution()));
          await repository.submit(aVote());
          await harness.change(
            meetingWith(aResolution(status: ResolutionStatus.closed)),
          );

          expect(await repository.submit(aVote()), equals(ok<void>(null)));
          expect(await harness.recordedCount(aVote()), equals(1));
        });

        test('still rejects a first vote once the window is over: '
            'the rule only protects a vote that was recorded', () async {
          await harness.serve(closingIn(halfAnHour));
          harness.advanceClock(halfAnHour + 1);

          expect(
            await repository.submit(aVote()),
            equals(err(const VotingWindowOverError())),
          );
        });
      });

      test('accepts a vote whose castAt, from the clock of the device, '
          'is after the closing instant '
          'while the time of the server is before it', () async {
        await harness.serve(
          meetingWith(
            aResolution(
              closesAt: unwrap(parseInstant(harness.now + millisPerHour)),
            ),
          ),
        );

        final result = await repository.submit(
          aVote(castAt: at(2 * millisPerHour)),
        );

        expect(result, equals(ok<void>(null)));
      });

      test('rejects a vote on a closed resolution', () async {
        await harness.serve(
          meetingWith(aResolution(status: ResolutionStatus.closed)),
        );

        expect(
          await repository.submit(aVote()),
          equals(err(const ResolutionClosedError())),
        );
        expect(await harness.recordedCount(aVote()), equals(0));
      });

      test('rejects a vote once the closing instant is reached, '
          'by the time of the server', () async {
        final closesAt = unwrap(parseInstant(harness.now - millisPerHour));
        await harness.serve(meetingWith(aResolution(closesAt: closesAt)));

        expect(
          await repository.submit(aVote(castAt: at(-10 * millisPerHour))),
          equals(err(const VotingWindowOverError())),
        );
      });

      test('accepts a vote while the closing instant is ahead', () async {
        final closesAt = unwrap(parseInstant(harness.now + millisPerHour));
        await harness.serve(meetingWith(aResolution(closesAt: closesAt)));

        expect(await repository.submit(aVote()), equals(ok<void>(null)));
      });

      test(
        'rejects the vote of a participant whose role carries no vote',
        () async {
          await harness.serve(meetingWith(aResolution()));
          await harness.authenticateAs(_secretary);

          expect(
            await repository.submit(aVote(voterId: _secretary)),
            equals(err(const NoVotingRightsError())),
          );
        },
      );

      test('rejects the vote of somebody who is not invited '
          'to the meeting', () async {
        await harness.serve(meetingWith(aResolution()));
        await harness.authenticateAs(_outsider);

        expect(
          await repository.submit(aVote(voterId: _outsider)),
          equals(err(const NotAParticipantError())),
        );
      });

      test('rejects a vote on a resolution the meeting does not have, '
          'or in a meeting it does not hold', () async {
        await harness.serve(meetingWith(aResolution()));
        final unknown = aResolutionId('does-not-exist');

        expect(
          await repository.submit(aVote(resolutionId: unknown)),
          equals(err(ResolutionNotFoundError(resolutionId: unknown))),
        );
        expect(
          await repository.submit(
            aVote(meetingId: aMeetingId('does-not-exist')),
          ),
          equals(err(ResolutionNotFoundError(resolutionId: aResolutionId()))),
        );
      });
    }, skip: !options.enforcesBusinessRules);
  });
}
