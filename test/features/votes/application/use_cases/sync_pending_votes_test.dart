import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/ports/vote_outbox.dart';
import 'package:boardroom/features/votes/application/use_cases/sync_pending_votes.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/builders/names.dart';
import '../../../../support/fakes/create_fakes.dart';
import '../../../../support/fakes/fake_monitoring.dart';
import '../../../../support/fakes/fake_vote_outbox.dart';
import 'votes_support.dart';

// Three votes of user-1, on three resolutions, queued oldest first. Each was
// cast, and queued, before the clock of the tests (`now`) started: a run that
// stamped a vote with the clock again would send another instant than the one
// it was cast at.
final PendingVote _first = aPendingVote(
  aVote(resolutionId: aResolutionId('r1'), castAt: at(-3000)),
  at(-3000),
);
final PendingVote _second = aPendingVote(
  aVote(
    resolutionId: aResolutionId('r2'),
    choice: VoteChoice.against,
    castAt: at(-2000),
  ),
  at(-2000),
);
final PendingVote _third = aPendingVote(
  aVote(
    resolutionId: aResolutionId('r3'),
    choice: VoteChoice.abstain,
    castAt: at(-1000),
  ),
  at(-1000),
);

const VotingError _closed = ResolutionClosedError();

/// The resolutions of some votes: what a report names.
List<ResolutionId> _ids(List<OutboxVote> entries) => [
  for (final entry in entries) entry.vote.resolutionId,
];

({Fakes fakes, SyncPendingVotes useCase}) _setup([
  List<OutboxVote> entries = const [],
]) {
  final fakes = createFakes();
  fakes.outbox.seed(entries);
  return (fakes: fakes, useCase: SyncPendingVotes(fakes));
}

/// What the outbox holds for each key: its resolution, its status and its
/// attempts.
List<(ResolutionId, OutboxStatus, int)> _states(Fakes fakes) => [
  for (final entry in fakes.outbox.snapshot())
    (entry.vote.resolutionId, entry.status, entry.attempts),
];

/// A report that has the given properties (the others are not looked at):
/// the Dart counterpart of `toMatchObject`.
Matcher _isReport({
  SyncOutcome? outcome,
  List<ResolutionId>? synced,
  List<RejectedSync>? rejected,
  int? remaining,
  AppError? interruptedBy,
}) => allOf([
  isNotNull,
  if (outcome != null)
    isA<SyncReport>().having((report) => report.outcome, 'outcome', outcome),
  if (synced != null)
    isA<SyncProgress>().having((report) => report.synced, 'synced', synced),
  if (rejected != null)
    isA<SyncProgress>().having(
      (report) => report.rejected,
      'rejected',
      rejected,
    ),
  if (remaining != null)
    isA<SyncProgress>().having(
      (report) => report.remaining,
      'remaining',
      remaining,
    ),
  if (interruptedBy != null)
    isA<SyncInterrupted>().having(
      (report) => report.interruptedBy,
      'interruptedBy',
      interruptedBy,
    ),
]);

SyncCompleted _completed({
  List<ResolutionId> synced = const [],
  List<RejectedSync> rejected = const [],
  int remaining = 0,
}) => SyncCompleted(synced: synced, rejected: rejected, remaining: remaining);

/// An outbox whose second read, and the ones after it, fail.
final class _FlakyOutbox extends FakeVoteOutbox {
  new(this._failure);

  final StorageReadFailedError _failure;
  int _reads = 0;

  @override
  Future<Result<OutboxListing, StorageReadFailedError>> list(UserId voterId) {
    _reads += 1;
    return _reads == 1 ? super.list(voterId) : Future.value(err(_failure));
  }
}

/// An outbox that signs somebody else in while it is read.
final class _SwitchingOutbox extends FakeVoteOutbox {
  new(this._fakes);

  final Fakes _fakes;

  @override
  Future<Result<OutboxListing, StorageReadFailedError>> list(
    UserId voterId,
  ) async {
    final listed = await super.list(voterId);
    _fakes.auth.session = aSession(
      user: aUser(id: aUserId('user-B'), email: anEmail('b@example.com')),
    );
    return listed;
  }
}

/// An outbox that breaks its contract: its read throws.
final class _RejectingOutbox extends FakeVoteOutbox {
  @override
  Future<Result<OutboxListing, StorageReadFailedError>> list(UserId voterId) =>
      Future.error(Exception('outbox exploded'));
}

Matcher _explosion() => throwsA(
  isA<Exception>().having(
    (error) => '$error',
    'message',
    contains('outbox exploded'),
  ),
);

void main() {
  group('SyncPendingVotes', () {
    group('when everything goes through', () {
      test('sends the votes oldest first and empties the outbox', () async {
        final (:fakes, :useCase) = _setup([_first, _second, _third]);

        final result = await useCase.execute();

        expect(
          result,
          equals(ok(_completed(synced: _ids([_first, _second, _third])))),
        );
        expect(
          fakes.votes.received,
          equals([_first.vote, _second.vote, _third.vote]),
        );
        expect(
          fakes.votes.recordedVotes(),
          equals([_first.vote, _second.vote, _third.vote]),
        );
        expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
      });

      test('sends each vote as it was cast: the instant of the cast is not '
          'renewed by the clock', () async {
        final (:fakes, :useCase) = _setup([_first, _second]);
        fakes.clock.advance(90000);

        await useCase.execute();

        expect(
          fakes.votes.received.map((vote) => vote.castAt).toList(),
          equals([at(-3000), at(-2000)]),
        );
        expect(
          fakes.votes.recordedVotes().map((vote) => vote.castAt).toList(),
          equals([at(-3000), at(-2000)]),
        );
      });

      test('sends the votes in the order of the outbox, which neither their '
          'resolution ids nor their instants would give', () async {
        final queuedFirst = aPendingVote(
          aVote(resolutionId: aResolutionId('r9'), castAt: at(-500)),
          at(-3000),
        );
        final queuedSecond = aPendingVote(
          aVote(resolutionId: aResolutionId('r1'), castAt: at(-9000)),
          at(-2000),
        );
        final queuedThird = aPendingVote(
          aVote(resolutionId: aResolutionId('r5'), castAt: at(-4000)),
          at(-1000),
        );
        final (:fakes, :useCase) = _setup([
          queuedFirst,
          queuedSecond,
          queuedThird,
        ]);

        await useCase.execute();

        expect(
          fakes.votes.received,
          equals([queuedFirst.vote, queuedSecond.vote, queuedThird.vote]),
        );
      });

      test('has nothing to do with an empty outbox', () async {
        final (:fakes, :useCase) = _setup();

        expect(await useCase.execute(), equals(ok(_completed())));
        expect(fakes.votes.received, equals(<Vote>[]));
      });

      test('logs a summary with counts only', () async {
        final (:fakes, :useCase) = _setup([_first, _second]);

        await useCase.execute();

        expect(
          fakes.monitoring.logs,
          equals([
            const LogRecord(
              level: LogLevel.info,
              event: MonitoringEvent.voteSyncCompleted,
              attributes: {
                LogAttribute.synced: 2,
                LogAttribute.rejected: 0,
                LogAttribute.remaining: 0,
              },
            ),
          ]),
        );
      });
    });

    group('the cached meeting of a vote the server recorded', () {
      Future<VoteChoice?> cachedChoice(Fakes fakes) async {
        final cached = await fakes.meetingCache.readMeeting(
          aUserId(),
          aMeetingId(),
        );
        final entry = valueOf(cached);
        if (entry == null) {
          return null;
        }
        return findResolution(entry.value, aResolutionId())?.recordedVote;
      }

      test('shows the vote after the synchronisation, and keeps its '
          'date', () async {
        final (:fakes, :useCase) = _setup([
          aPendingVote(
            aVote(choice: VoteChoice.against, resolutionId: aResolutionId()),
          ),
        ]);
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), at(-5000));

        await useCase.execute();

        expect(await cachedChoice(fakes), equals(VoteChoice.against));
        final cached = await fakes.meetingCache.readMeeting(
          aUserId(),
          aMeetingId(),
        );
        expect(valueOf(cached)?.cachedAt, equals(at(-5000)));
      });

      test('is fine when the meeting is not cached', () async {
        final (:fakes, :useCase) = _setup([_first]);

        final result = await useCase.execute();

        expect(valueOf(result)?.outcome, equals(SyncOutcome.completed));
        expect(fakes.meetingCache.isEmpty(), isTrue);
      });

      test('does not fail the run when the cache cannot be written, and '
          'captures it', () async {
        final (:fakes, :useCase) = _setup([
          aPendingVote(aVote(resolutionId: aResolutionId())),
        ]);
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
        fakes.meetingCache.writeFailure = storageWriteFailed();

        final result = await useCase.execute();

        expect(valueOf(result), _isReport(outcome: SyncOutcome.completed));
        expect(
          fakes.monitoring.capturedEvents(),
          equals([MonitoringEvent.cacheWriteFailed]),
        );
      });

      test('is not touched by a vote that did not go through', () async {
        final (:fakes, :useCase) = _setup([
          aPendingVote(aVote(resolutionId: aResolutionId())),
        ]);
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
        fakes.network.goOffline();

        await useCase.execute();

        expect(await cachedChoice(fakes), isNull);
      });
    });

    group('when the server rejects a vote for a business reason', () {
      test('keeps it in the outbox as rejected, with its reason, and carries '
          'on', () async {
        final (:fakes, :useCase) = _setup([_first, _second, _third]);
        fakes.clock.advance(1000);
        fakes.votes.answerNext(ok<void>(null));
        fakes.votes.answerNext(err(_closed));

        final result = await useCase.execute();

        final rejected = RejectedVote(
          vote: _second.vote,
          enqueuedAt: _second.enqueuedAt,
          attempts: 0,
          reason: _closed,
          rejectedAt: at(1000),
        );
        expect(
          result,
          equals(
            ok(
              _completed(
                synced: _ids([_first, _third]),
                rejected: [
                  RejectedSync(
                    resolutionId: _second.vote.resolutionId,
                    reason: _closed,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(fakes.outbox.snapshot(), equals([rejected]));
      });

      for (final reason in <VotingError>[
        const AlreadyVotedError(source: AlreadyVotedSource.recorded),
        const NotAParticipantError(),
        const VotingWindowOverError(),
      ]) {
        test('treats ${formatPretty(reason)} as a rejection too, and keeps '
            'the reason', () async {
          final (:fakes, :useCase) = _setup([_first]);
          fakes.votes.answerNext(err(reason));

          await useCase.execute();

          expect(fakes.outbox.snapshot(), [
            isA<RejectedVote>().having(
              (entry) => entry.reason,
              'reason',
              reason,
            ),
          ]);
        });
      }

      test('never sends a rejected vote again', () async {
        final (:fakes, :useCase) = _setup([_first, _second]);
        fakes.votes.answerNext(err(_closed));
        await useCase.execute();

        final second = await useCase.execute();

        expect(fakes.votes.received, equals([_first.vote, _second.vote]));
        expect(second, equals(ok(_completed())));
      });

      test('leaves alone a vote that was already rejected before the '
          'run', () async {
        final already = aRejectedVote(aVote(resolutionId: aResolutionId('r9')));
        final (:fakes, :useCase) = _setup([already, _first]);

        await useCase.execute();

        expect(fakes.votes.received, equals([_first.vote]));
        expect(fakes.outbox.snapshot(), equals([already]));
      });

      test('logs it with the reason and the attempts', () async {
        final (:fakes, :useCase) = _setup([_first]);
        fakes.votes.answerNext(err(_closed));

        await useCase.execute();

        expect(
          fakes.monitoring.logs.first,
          equals(
            LogRecord(
              level: LogLevel.warn,
              event: MonitoringEvent.voteRejected,
              attributes: {
                LogAttribute.resolutionId: aResolutionId('r1'),
                LogAttribute.errorCode: _closed.code,
                LogAttribute.attempts: 0,
              },
            ),
          ),
        );
      });

      test('stops, and reports nothing as rejected, when the outbox cannot '
          'record the rejection', () async {
        final (:fakes, :useCase) = _setup([_first, _second]);
        fakes.votes.answerNext(err(_closed));
        fakes.outbox.rejectFailure = storageWriteFailed();

        final result = await useCase.execute();

        expect(
          result,
          equals(
            ok(
              SyncInterrupted(
                synced: const [],
                rejected: const [],
                remaining: 2,
                interruptedBy: storageWriteFailed(),
              ),
            ),
          ),
        );
        expect(fakes.votes.received, equals([_first.vote]));
      });
    });

    group('the monitoring of a run that contains a rejection', () {
      test('logs the counters of the run, and the code that stopped '
          'it', () async {
        final (:fakes, :useCase) = _setup([_first, _second, _third]);
        fakes.votes.answerNext(ok<void>(null));
        fakes.votes.answerNext(err(_closed));
        fakes.votes.answerNext(err(networkUnavailable()));

        await useCase.execute();

        expect(
          fakes.monitoring.logs,
          equals([
            LogRecord(
              level: LogLevel.warn,
              event: MonitoringEvent.voteRejected,
              attributes: {
                LogAttribute.resolutionId: aResolutionId('r2'),
                LogAttribute.errorCode: _closed.code,
                LogAttribute.attempts: 0,
              },
            ),
            LogRecord(
              level: LogLevel.warn,
              event: MonitoringEvent.voteSyncInterrupted,
              attributes: {
                LogAttribute.synced: 1,
                LogAttribute.rejected: 1,
                LogAttribute.remaining: 1,
                LogAttribute.errorCode: networkUnavailable().code,
              },
            ),
          ]),
        );
      });

      test('logs the counters of a run that went through, rejection '
          'included', () async {
        final (:fakes, :useCase) = _setup([_first, _second, _third]);
        fakes.votes.answerNext(err(_closed));

        await useCase.execute();

        expect(
          fakes.monitoring.logs.last,
          equals(
            const LogRecord(
              level: LogLevel.info,
              event: MonitoringEvent.voteSyncCompleted,
              attributes: {
                LogAttribute.synced: 2,
                LogAttribute.rejected: 1,
                LogAttribute.remaining: 0,
              },
            ),
          ),
        );
      });

      test('captures a vote it gave up on with the id of the resolution and '
          'the attempts', () async {
        final fakes = createFakes();
        fakes.outbox.seed([_first]);
        fakes.votes.answerNext(err(unexpected('HTTP 500')));

        await SyncPendingVotes(fakes.copyWith(maxAttempts: 1)).execute();

        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.voteSubmitFailed,
              error: unexpected('HTTP 500'),
              attributes: {LogAttribute.resolutionId: aResolutionId('r1')},
            ),
          ]),
        );
        expect(
          fakes.monitoring.logs.first,
          equals(
            LogRecord(
              level: LogLevel.warn,
              event: MonitoringEvent.voteRejected,
              attributes: {
                LogAttribute.resolutionId: aResolutionId('r1'),
                LogAttribute.errorCode: voteUndeliverable(1).code,
                LogAttribute.attempts: 1,
              },
            ),
          ),
        );
      });

      test('captures a failure to count an attempt with the id of the '
          'resolution', () async {
        final (:fakes, :useCase) = _setup([_first]);
        fakes.votes.answerNext(err(unexpected()));
        fakes.outbox.markAttemptFailure = storageWriteFailed();

        await useCase.execute();

        expect(
          fakes.monitoring.errors[1],
          equals(
            ErrorRecord(
              event: MonitoringEvent.voteAttemptNotRecorded,
              error: storageWriteFailed(),
              attributes: {LogAttribute.resolutionId: aResolutionId('r1')},
            ),
          ),
        );
      });

      test('captures the outbox that cannot be read again with the dedicated '
          'event', () async {
        final fakes = createFakes();
        final outbox = _FlakyOutbox(storageReadFailed('x'))..seed([_first]);

        await SyncPendingVotes(VotesDeps(fakes, outbox: outbox)).execute();

        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.outboxReadFailed,
              error: storageReadFailed('x'),
              attributes: null,
            ),
          ]),
        );
      });
    });

    group('when the network is unavailable', () {
      test('stops at once and keeps every pending vote, without counting an '
          'attempt', () async {
        final (:fakes, :useCase) = _setup([_first, _second, _third]);
        fakes.network.goOffline();

        final result = await useCase.execute();

        expect(
          result,
          equals(
            ok(
              SyncInterrupted(
                synced: const [],
                rejected: const [],
                remaining: 3,
                interruptedBy: networkUnavailable(),
              ),
            ),
          ),
        );
        expect(fakes.votes.received, equals([_first.vote]));
        expect(fakes.outbox.snapshot(), equals([_first, _second, _third]));
      });

      test('never makes a vote undeliverable, however many times the user is '
          'offline', () async {
        final (:fakes, :useCase) = _setup([_first]);
        fakes.network.goOffline();
        for (var run = 0; run < 20; run += 1) {
          await useCase.execute();
        }

        expect(fakes.outbox.snapshot(), equals([_first]));
      });

      test('keeps what was settled before the network dropped, and what '
          'comes after', () async {
        final (:fakes, :useCase) = _setup([_first, _second, _third]);
        fakes.votes.answerNext(ok<void>(null));
        fakes.votes.answerNext(err(networkUnavailable()));

        final result = await useCase.execute();

        expect(
          result,
          equals(
            ok(
              SyncInterrupted(
                synced: _ids([_first]),
                rejected: const [],
                remaining: 2,
                interruptedBy: networkUnavailable(),
              ),
            ),
          ),
        );
        expect(fakes.votes.received, equals([_first.vote, _second.vote]));
        expect(fakes.outbox.snapshot(), equals([_second, _third]));
      });

      test('goes on from where it stopped on the next run', () async {
        final (:fakes, :useCase) = _setup([_first, _second]);
        fakes.network.goOffline();
        await useCase.execute();
        fakes.network.goOnline();

        final result = await useCase.execute();

        expect(
          valueOf(result),
          _isReport(
            outcome: SyncOutcome.completed,
            synced: _ids([_first, _second]),
          ),
        );
        expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
      });

      test('logs that the run was interrupted, with the cause', () async {
        final (:fakes, :useCase) = _setup([_first, _second]);
        fakes.network.goOffline();

        await useCase.execute();

        expect(
          fakes.monitoring.logs,
          equals([
            LogRecord(
              level: LogLevel.warn,
              event: MonitoringEvent.voteSyncInterrupted,
              attributes: {
                LogAttribute.synced: 0,
                LogAttribute.rejected: 0,
                LogAttribute.remaining: 2,
                LogAttribute.errorCode: networkUnavailable().code,
              },
            ),
          ]),
        );
      });
    });

    group('when the server refuses the user', () {
      test('stops, keeps every vote pending and says why, without counting '
          'an attempt', () async {
        final (:fakes, :useCase) = _setup([_first, _second]);
        fakes.votes.answerNext(err(unauthorized()));

        final result = await useCase.execute();

        expect(
          valueOf(result),
          _isReport(
            outcome: SyncOutcome.interrupted,
            remaining: 2,
            interruptedBy: unauthorized(),
          ),
        );
        expect(fakes.votes.received, equals([_first.vote]));
        expect(fakes.outbox.snapshot(), equals([_first, _second]));
      });

      test('ends the session on the device and keeps the votes for the next '
          'time their voter signs in', () async {
        final (:fakes, :useCase) = _setup([_first, _second]);
        fakes.votes.answerNext(err(unauthorized()));

        await useCase.execute();

        expect(fakes.auth.signOutCalls, equals(1));
        expect(fakes.auth.session, isNull);
        expect(fakes.appLock.isLocked(), isTrue);
        expect(fakes.outbox.snapshot(), equals([_first, _second]));
      });

      test('does not sign out somebody else who signed in meanwhile: that '
          'session was not refused', () async {
        final (:fakes, :useCase) = _setup([_first, _second]);
        fakes.votes.onReceive = (_) {
          fakes.auth.session = aSession(user: aUser(id: aUserId('user-2')));
        };
        fakes.votes.answerNext(err(unauthorized()));

        await useCase.execute();

        expect(fakes.auth.signOutCalls, equals(0));
        expect(fakes.auth.session?.user.id, equals(aUserId('user-2')));
      });

      test('captures a session that cannot be forgotten, and still reports '
          'the interruption', () async {
        final (:fakes, :useCase) = _setup([_first]);
        fakes.auth.signOutFailure = storageWriteFailed();
        fakes.votes.answerNext(err(unauthorized()));

        final result = await useCase.execute();

        expect(valueOf(result), _isReport(interruptedBy: unauthorized()));
        expect(
          fakes.monitoring.capturedEvents(),
          contains(MonitoringEvent.signOutFailed),
        );
      });
    });

    group('when the server fails unexpectedly on one vote', () {
      test('counts an attempt, captures the failure and carries on with the '
          'next vote', () async {
        final (:fakes, :useCase) = _setup([_first, _second, _third]);
        fakes.votes.answerNext(err(unexpected('HTTP 500')));

        final result = await useCase.execute();

        expect(
          result,
          equals(ok(_completed(synced: _ids([_second, _third]), remaining: 1))),
        );
        expect(
          fakes.votes.received,
          equals([_first.vote, _second.vote, _third.vote]),
        );
        expect(fakes.outbox.snapshot(), equals([_first.copyWith(attempts: 1)]));
        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.voteSubmitFailed,
              error: unexpected('HTTP 500'),
              attributes: {LogAttribute.resolutionId: aResolutionId('r1')},
            ),
          ]),
        );
      });

      test('keeps the vote and tries it again on the next run, where the '
          'attempts add up', () async {
        final (:fakes, :useCase) = _setup([_first]);
        fakes.votes.answerNext(err(unexpected()));
        fakes.votes.answerNext(err(unexpected()));
        await useCase.execute();
        await useCase.execute();

        expect(
          _states(fakes),
          equals([(aResolutionId('r1'), OutboxStatus.pending, 2)]),
        );

        final result = await useCase.execute();

        expect(valueOf(result), _isReport(synced: _ids([_first])));
      });

      test('gives the vote up after the maximum number of attempts, as '
          'undeliverable, for the user to see', () async {
        final fakes = createFakes();
        fakes.outbox.seed([_first]);
        final useCase = SyncPendingVotes(fakes.copyWith(maxAttempts: 3));
        for (var run = 0; run < 3; run += 1) {
          fakes.votes.answerNext(err(unexpected()));
        }

        await useCase.execute();
        await useCase.execute();
        expect(
          _states(fakes),
          equals([(aResolutionId('r1'), OutboxStatus.pending, 2)]),
        );
        fakes.clock.advance(5000);
        final result = await useCase.execute();

        final rejected = RejectedVote(
          vote: _first.vote,
          enqueuedAt: _first.enqueuedAt,
          attempts: 3,
          reason: voteUndeliverable(3),
          rejectedAt: at(5000),
        );
        expect(fakes.outbox.snapshot(), equals([rejected]));
        expect(
          result,
          equals(
            ok(
              _completed(
                rejected: [
                  RejectedSync(
                    resolutionId: _first.vote.resolutionId,
                    reason: voteUndeliverable(3),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(fakes.votes.received, hasLength(3));
      });

      test('does not let one bad vote block the others for ever', () async {
        final fakes = createFakes();
        fakes.outbox.seed([_first, _second]);
        final useCase = SyncPendingVotes(fakes.copyWith(maxAttempts: 2));
        fakes.votes.onReceive = (vote) {
          if (vote.resolutionId == _first.vote.resolutionId) {
            fakes.votes.answerNext(err(unexpected()));
          }
        };

        await useCase.execute();
        fakes.outbox.seed([_third]);
        await useCase.execute();

        expect(
          fakes.votes.recordedVotes(),
          equals([_second.vote, _third.vote]),
        );
        expect(
          _states(fakes),
          equals([(aResolutionId('r1'), OutboxStatus.rejected, 2)]),
        );
      });

      test('still counts the attempt for its decision, and captures it, when '
          'the outbox cannot record it', () async {
        final fakes = createFakes();
        fakes.outbox.seed([_first]);
        final useCase = SyncPendingVotes(fakes.copyWith(maxAttempts: 1));
        fakes.votes.answerNext(err(unexpected()));
        fakes.outbox.markAttemptFailure = storageWriteFailed();

        await useCase.execute();

        expect(
          fakes.monitoring.capturedEvents(),
          equals([
            MonitoringEvent.voteSubmitFailed,
            MonitoringEvent.voteAttemptNotRecorded,
          ]),
        );
        expect(fakes.outbox.snapshot(), [
          isA<RejectedVote>().having(
            (entry) => entry.reason,
            'reason',
            voteUndeliverable(1),
          ),
        ]);
      });
    });

    group('when the outbox cannot be updated', () {
      test('stops and does not report as settled a vote that is still '
          'pending', () async {
        final (:fakes, :useCase) = _setup([_first, _second]);
        fakes.outbox.removeFailure = storageWriteFailed();

        final result = await useCase.execute();

        expect(
          result,
          equals(
            ok(
              SyncInterrupted(
                synced: const [],
                rejected: const [],
                remaining: 2,
                interruptedBy: storageWriteFailed(),
              ),
            ),
          ),
        );
        expect(fakes.votes.received, equals([_first.vote]));
      });

      test('sends the vote again on the next run, and the server still holds '
          'it once', () async {
        final (:fakes, :useCase) = _setup([_first]);
        fakes.outbox.removeFailure = storageWriteFailed();
        await useCase.execute();
        fakes.outbox.removeFailure = null;

        final result = await useCase.execute();

        expect(
          valueOf(result),
          _isReport(outcome: SyncOutcome.completed, synced: _ids([_first])),
        );
        expect(fakes.votes.received, equals([_first.vote, _first.vote]));
        expect(fakes.votes.recordedVotes(), equals([_first.vote]));
        expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
      });

      test(
        'returns the storage error when the outbox cannot be read',
        () async {
          final (:fakes, :useCase) = _setup([_first]);
          fakes.outbox.listFailure = storageReadFailed();

          expect(await useCase.execute(), equals(err(storageReadFailed())));
          expect(fakes.votes.received, equals(<Vote>[]));
        },
      );
    });

    group('the number of votes still pending', () {
      test('is counted again from the outbox after the run, which may have '
          'changed meanwhile', () async {
        final (:fakes, :useCase) = _setup([_first]);
        final castMeanwhile = aPendingVote(
          aVote(resolutionId: aResolutionId('r7')),
        );
        fakes.votes.onReceive = (_) => fakes.outbox.seed([castMeanwhile]);

        final result = await useCase.execute();

        expect(
          valueOf(result),
          _isReport(synced: _ids([_first]), remaining: 1),
        );
      });

      test('falls back on what the run knows, and captures the failure, when '
          'the outbox cannot be read again', () async {
        final fakes = createFakes();
        final outbox = _FlakyOutbox(storageReadFailed())
          ..seed([_first, _second]);
        fakes.votes.answerNext(ok<void>(null));
        fakes.votes.answerNext(err(networkUnavailable()));

        final result = await SyncPendingVotes(VotesDeps(fakes, outbox: outbox))
            .execute();

        expect(
          valueOf(result),
          _isReport(synced: _ids([_first]), remaining: 1),
        );
        expect(
          fakes.monitoring.capturedEvents(),
          equals([MonitoringEvent.outboxReadFailed]),
        );
      });
    });

    group('whose votes it sends', () {
      test('only those of the signed-in user, and leaves the others '
          'untouched', () async {
        final others = aPendingVote(
          aVote(voterId: aUserId('user-2'), resolutionId: aResolutionId('r9')),
        );
        final (:fakes, :useCase) = _setup([_first, others, _second]);

        final result = await useCase.execute();

        expect(
          valueOf(result),
          _isReport(
            outcome: SyncOutcome.completed,
            synced: _ids([_first, _second]),
            remaining: 0,
          ),
        );
        expect(fakes.votes.received, equals([_first.vote, _second.vote]));
        expect(fakes.outbox.snapshot(), equals([others]));
      });

      test('does not count the votes of others as remaining', () async {
        final others = aPendingVote(aVote(voterId: aUserId('user-2')));
        final (:fakes, :useCase) = _setup([_first, others]);
        fakes.network.goOffline();

        final result = await useCase.execute();

        expect(valueOf(result), _isReport(remaining: 1));
      });
    });

    group('the session', () {
      test('is required: nothing is sent without it', () async {
        final (:fakes, :useCase) = _setup([_first]);
        fakes.auth.session = null;

        expect(await useCase.execute(), equals(err(notAuthenticated())));
        expect(fakes.votes.received, equals(<Vote>[]));
        expect(fakes.outbox.snapshot(), equals([_first]));
      });

      test('must not have expired: the votes wait for the next '
          'sign-in', () async {
        final (:fakes, :useCase) = _setup([_first]);
        fakes.auth.session = aSession(expiresAt: now);

        expect(await useCase.execute(), equals(err(sessionExpired())));
        expect(fakes.outbox.snapshot(), equals([_first]));
      });

      group('the lock of the app', () {
        test('does not run while the app is locked: nothing is sent, '
            'nothing changes in the outbox', () async {
          final (:fakes, :useCase) = _setup([_first, _second]);
          fakes.appLock.lock();

          expect(await useCase.execute(), equals(err(appLocked())));
          expect(fakes.votes.received, equals(<Vote>[]));
          expect(fakes.outbox.snapshot(), equals([_first, _second]));
        });

        test('runs again once the app is unlocked, and sends what '
            'waited', () async {
          final (:fakes, :useCase) = _setup([_first]);
          fakes.appLock.lock();
          await useCase.execute();
          fakes.appLock.unlock();

          final result = await useCase.execute();

          expect(valueOf(result), _isReport(synced: _ids([_first])));
        });

        test('stops at the next vote when the app is locked in the middle '
            'of a run', () async {
          final (:fakes, :useCase) = _setup([_first, _second, _third]);
          fakes.votes.answerNext(ok<void>(null));
          fakes.votes.onReceive = (_) => fakes.appLock.lock();

          final result = await useCase.execute();

          expect(
            valueOf(result),
            _isReport(
              outcome: SyncOutcome.interrupted,
              interruptedBy: appLocked(),
              synced: _ids([_first]),
              remaining: 2,
            ),
          );
          expect(fakes.votes.received, equals([_first.vote]));
        });
      });

      test('reports resolutions and reasons only: the choice of a vote is '
          'never in the report', () async {
        final (:fakes, :useCase) = _setup([_first, _second]);
        fakes.votes.answerNext(ok<void>(null));
        fakes.votes.answerNext(err(_closed));

        final result = await useCase.execute();

        final text = '$result';
        expect(text, isNot(contains('choice')));
        for (final choice in VoteChoice.values) {
          expect(text, isNot(contains(choice.value)));
        }
        expect(
          valueOf(result),
          _isReport(
            synced: _ids([_first]),
            rejected: [
              RejectedSync(
                resolutionId: _second.vote.resolutionId,
                reason: _closed,
              ),
            ],
          ),
        );
      });

      group('is checked again before each vote', () {
        test('stops the run when another user signs in meanwhile: the votes '
            'of A are not sent under B', () async {
          final (:fakes, :useCase) = _setup([_first, _second, _third]);
          fakes.votes.answerNext(ok<void>(null));
          fakes.votes.onReceive = (_) {
            fakes.auth.session = aSession(
              user: aUser(
                id: aUserId('user-B'),
                email: anEmail('b@example.com'),
              ),
            );
          };

          final result = await useCase.execute();

          expect(
            result,
            equals(
              ok(
                SyncInterrupted(
                  synced: _ids([_first]),
                  rejected: const [],
                  remaining: 2,
                  interruptedBy: sessionChanged(),
                ),
              ),
            ),
          );
          expect(fakes.votes.received, equals([_first.vote]));
          expect(fakes.outbox.snapshot(), equals([_second, _third]));
        });

        test('stops the run when the user signs out meanwhile', () async {
          final (:fakes, :useCase) = _setup([_first, _second]);
          fakes.votes.answerNext(ok<void>(null));
          fakes.votes.onReceive = (_) {
            fakes.auth.session = null;
          };

          final result = await useCase.execute();

          expect(
            valueOf(result),
            _isReport(
              outcome: SyncOutcome.interrupted,
              interruptedBy: notAuthenticated(),
              remaining: 1,
            ),
          );
          expect(fakes.votes.received, equals([_first.vote]));
        });

        test('stops the run when the session expires meanwhile', () async {
          final (:fakes, :useCase) = _setup([_first, _second]);
          fakes.votes.answerNext(ok<void>(null));
          fakes.votes.onReceive = (_) => fakes.clock.set(at(3600000));

          final result = await useCase.execute();

          expect(
            valueOf(result),
            _isReport(
              outcome: SyncOutcome.interrupted,
              interruptedBy: sessionExpired(),
            ),
          );
          expect(fakes.votes.received, equals([_first.vote]));
        });

        test('also checks before the first vote: the user may change while '
            'the outbox is being read', () async {
          final fakes = createFakes();
          final outbox = _SwitchingOutbox(fakes)..seed([_first]);

          final result = await SyncPendingVotes(
            VotesDeps(fakes, outbox: outbox),
          ).execute();

          expect(
            valueOf(result),
            _isReport(
              outcome: SyncOutcome.interrupted,
              interruptedBy: sessionChanged(),
              remaining: 1,
            ),
          );
          expect(fakes.votes.received, equals(<Vote>[]));
        });

        test('keeps going while it is the same user', () async {
          final (:fakes, :useCase) = _setup([_first, _second, _third]);

          await useCase.execute();

          expect(fakes.votes.received, hasLength(3));
        });
      });
    });

    group('overlapping calls', () {
      test('makes a call a no-op while a run is in progress, and sends each '
          'vote once', () async {
        final (:fakes, :useCase) = _setup([_first, _second]);

        final [first, second] = await Future.wait([
          useCase.execute(),
          useCase.execute(),
        ]);

        expect(valueOf(first)?.outcome, equals(SyncOutcome.completed));
        expect(second, equals(ok(const SyncAlreadyRunning())));
        expect(fakes.votes.received, equals([_first.vote, _second.vote]));
      });

      test('accepts a new run once the previous one is over', () async {
        final (:fakes, :useCase) = _setup([_first]);
        await useCase.execute();
        fakes.outbox.seed([_second]);

        final result = await useCase.execute();

        expect(
          valueOf(result),
          _isReport(outcome: SyncOutcome.completed, synced: _ids([_second])),
        );
      });

      test('releases the guard even when a port breaks its contract and '
          'rejects', () async {
        final fakes = createFakes();
        final useCase = SyncPendingVotes(
          VotesDeps(fakes, outbox: _RejectingOutbox()),
        );

        await expectLater(useCase.execute(), _explosion());

        final healthy = SyncPendingVotes(fakes);
        expect(await healthy.execute(), equals(ok(_completed())));
        await expectLater(useCase.execute(), _explosion());
      });

      test('does not share its guard between instances: both send the vote, '
          'and the idempotency key keeps it recorded once', () async {
        final fakes = createFakes();
        fakes.outbox.seed([_first]);
        final a = SyncPendingVotes(fakes);
        final b = SyncPendingVotes(fakes);

        final [first, second] = await Future.wait([a.execute(), b.execute()]);

        expect(valueOf(first)?.outcome, equals(SyncOutcome.completed));
        expect(valueOf(second)?.outcome, equals(SyncOutcome.completed));
        expect(fakes.votes.received, equals([_first.vote, _first.vote]));
        expect(fakes.votes.recordedVotes(), equals([_first.vote]));
      });
    });
  });
}
