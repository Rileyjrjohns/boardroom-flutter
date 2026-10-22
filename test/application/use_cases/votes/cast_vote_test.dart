import 'package:boardroom/application/ports/biometric_gate.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/ports/types/cache_entry.dart';
import 'package:boardroom/application/use_cases/votes/cast_vote.dart';
import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/domain/entities/participant.dart';
import 'package:boardroom/domain/entities/resolution.dart';
import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/vote_choice.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import '../../../domain/support/names.dart';
import '../../support/create_fakes.dart';
import '../../support/fake_clock.dart';
import '../../support/fake_monitoring.dart';
import '../../support/fake_vote_outbox.dart';
import 'votes_support.dart';

/// The default input: the vote of the tests, [choice] for.
_Input _input({
  MeetingId? meetingId,
  ResolutionId? resolutionId,
  VoteChoice choice = VoteChoice.forChoice,
}) => (
  meetingId: meetingId ?? aMeetingId(),
  resolutionId: resolutionId ?? aResolutionId(),
  choice: choice,
);

/// The three things a vote is cast with, as the tests pass them around
/// (`{ ...INPUT, choice }` in the React Native tests).
typedef _Input = ({
  MeetingId meetingId,
  ResolutionId resolutionId,
  VoteChoice choice,
});

extension on CastVote {
  /// Casts the vote of [input]: `execute(INPUT)` in the React Native tests.
  Future<Result<CastVoteOutcome, CastVoteError>> cast(_Input input) => execute(
    meetingId: input.meetingId,
    resolutionId: input.resolutionId,
    choice: input.choice,
  );
}

/// user-1 is signed in; the meeting is on the server; its resolution is open.
({Fakes fakes, CastVote useCase}) _setup([Meeting? meeting]) {
  final fakes = createFakes();
  fakes.meetings.addMeeting(meeting ?? aMeeting());
  return (fakes: fakes, useCase: CastVote(fakes));
}

/// A meeting whose only resolution is the given one.
Meeting _meetingWith(Resolution resolution) =>
    aMeeting(agenda: [anAgendaItem(resolution: resolution)]);

/// The attributes of what a vote logs: its meeting and its resolution.
Map<LogAttribute, Object> _voteAttributes() => {
  LogAttribute.meetingId: aMeetingId(),
  LogAttribute.resolutionId: aResolutionId(),
};

/// The choice recorded on the resolution in the cached copy of the meeting.
Future<VoteChoice?> _cachedChoice(
  Fakes fakes, [
  ResolutionId? resolutionId,
]) async {
  final cached = await fakes.meetingCache.readMeeting(aUserId(), aMeetingId());
  final entry = valueOf(cached);
  if (entry == null) {
    return null;
  }
  return findResolution(
    entry.value,
    resolutionId ?? aResolutionId(),
  )?.recordedVote;
}

/// The outbox when it cannot find what is queued under a resolution.
final class _BlindOutbox extends FakeVoteOutbox {
  @override
  Future<Result<List<OutboxVote>, StorageReadFailedError>> findByResolution(
    ResolutionId resolutionId,
    UserId voterId,
  ) async => ok(<OutboxVote>[]);
}

/// A biometric prompt that takes [_millis] to be answered.
final class _SlowGate implements BiometricGate {
  const new(this._inner, this._clock, this._millis);

  final BiometricGate _inner;
  final FakeClock _clock;
  final int _millis;

  @override
  Future<Result<void, BiometricAvailabilityError>> checkAvailability() =>
      _inner.checkAvailability();

  @override
  Future<Result<void, BiometricError>> authenticate(BiometricReason reason) {
    _clock.advance(_millis);
    return _inner.authenticate(reason);
  }
}

void main() {
  group('CastVote', () {
    group('with a network', () {
      test('submits the vote of the signed-in user, built with the clock, '
          'and reports it submitted', () async {
        final (:fakes, :useCase) = _setup();
        fakes.clock.advance(5000);

        final result = await useCase.cast(_input());

        final expectedVote = aVote(
          castAt: at(5000),
          // The choice is part of the scenario: it is spelled out.
          // ignore: avoid_redundant_argument_values
          choice: VoteChoice.forChoice,
        );
        expect(
          result,
          equals(
            ok(
              CastVoteOutcome(
                status: CastVoteStatus.submitted,
                vote: expectedVote,
              ),
            ),
          ),
        );
        expect(fakes.votes.recordedVotes(), equals([expectedVote]));
        expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
      });

      for (final choice in VoteChoice.values) {
        test('carries the choice ${choice.value}', () async {
          final (:fakes, :useCase) = _setup();

          await useCase.cast(_input(choice: choice));

          expect(
            fakes.votes.recordedVotes().map((vote) => vote.choice).toList(),
            equals([choice]),
          );
        });
      }

      test('asks for the biometric confirmation of the vote', () async {
        final (:fakes, :useCase) = _setup();

        await useCase.cast(_input());

        expect(
          fakes.biometricGate.prompts,
          equals([BiometricReason.confirmVote]),
        );
      });

      test('logs the vote with identifiers only, never the choice', () async {
        final (:fakes, :useCase) = _setup();

        await useCase.cast(_input(choice: VoteChoice.against));

        expect(
          fakes.monitoring.logs,
          equals([
            LogRecord(
              level: LogLevel.info,
              event: MonitoringEvent.voteSubmitted,
              attributes: _voteAttributes(),
            ),
          ]),
        );
        expect(
          '${fakes.monitoring.logs}',
          isNot(contains(VoteChoice.against.value)),
        );
      });

      test('lets the chair vote', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.session = aSession(
          user: aSession().user.copyWith(id: aUserId('user-2')),
        );

        final result = await useCase.cast(_input());

        expect(valueOf(result)?.vote.voterId, equals(aUserId('user-2')));
      });
    });

    group('without a network', () {
      test('queues the vote in the outbox and reports it queued', () async {
        final (:fakes, :useCase) = _setup();
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
        fakes.network.goOffline();
        fakes.clock.advance(2000);

        final result = await useCase.cast(_input());

        final expectedVote = aVote(castAt: at(2000));
        expect(
          result,
          equals(
            ok(
              CastVoteOutcome(
                status: CastVoteStatus.queued,
                vote: expectedVote,
              ),
            ),
          ),
        );
        expect(
          fakes.outbox.snapshot(),
          equals([
            PendingVote(vote: expectedVote, enqueuedAt: at(2000), attempts: 0),
          ]),
        );
        expect(fakes.votes.recordedVotes(), equals(<Vote>[]));
        expect(
          fakes.monitoring.loggedEvents(),
          equals([MonitoringEvent.servedFromCache, MonitoringEvent.voteQueued]),
        );
      });

      test('queues a vote cast right after the network dropped, from a '
          'meeting that is loaded fresh', () async {
        final (:fakes, :useCase) = _setup();
        fakes.votes.answerNext(err(networkUnavailable()));

        final result = await useCase.cast(_input());

        expect(valueOf(result)?.status, equals(CastVoteStatus.queued));
        expect(fakes.outbox.snapshot(), hasLength(1));
      });

      test('cannot vote on a meeting that was never loaded: nobody is asked '
          'for a confirmation', () async {
        final (:fakes, :useCase) = _setup();
        fakes.network.goOffline();

        expect(await useCase.cast(_input()), equals(err(networkUnavailable())));
        expect(fakes.biometricGate.prompts, equals(<BiometricReason>[]));
        expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
      });

      test('refuses a second vote on the same resolution while the first '
          'one is queued', () async {
        final (:fakes, :useCase) = _setup();
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
        fakes.network.goOffline();
        await useCase.cast(_input());
        fakes.biometricGate.prompts.clear();

        final second = await useCase.cast(_input(choice: VoteChoice.against));

        expect(
          second,
          equals(
            err(const AlreadyVotedError(source: AlreadyVotedSource.queued)),
          ),
        );
        expect(fakes.biometricGate.prompts, equals(<BiometricReason>[]));
        expect(fakes.outbox.snapshot(), hasLength(1));
      });

      test(
        'decides from the cached copy of the meeting, flagged stale',
        () async {
          final closed = _meetingWith(
            aResolution(status: ResolutionStatus.closed),
          );
          final (:fakes, :useCase) = _setup();
          await fakes.meetingCache.saveMeeting(aUserId(), closed, now);
          fakes.network.goOffline();

          expect(
            await useCase.cast(_input()),
            equals(err(const ResolutionClosedError())),
          );
          expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
        },
      );

      test('returns the storage error, and keeps no vote, when the outbox '
          'cannot be written', () async {
        final (:fakes, :useCase) = _setup();
        fakes.votes.answerNext(err(networkUnavailable()));
        fakes.outbox.enqueueFailure = storageWriteFailed();

        expect(await useCase.cast(_input()), equals(err(storageWriteFailed())));
        expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
      });
    });

    group('the session', () {
      test('is required', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.session = null;

        expect(await useCase.cast(_input()), equals(err(notAuthenticated())));
        expect(fakes.meetings.getCalls, equals(<MeetingId>[]));
        expect(fakes.biometricGate.prompts, equals(<BiometricReason>[]));
      });

      test('must not have expired', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.session = aSession(expiresAt: now);

        expect(await useCase.cast(_input()), equals(err(sessionExpired())));
      });
    });

    group('the eligibility', () {
      test('returns notFound for an unknown meeting', () async {
        final (:fakes, :useCase) = _setup();

        expect(
          await useCase.cast(_input(meetingId: aMeetingId('missing'))),
          equals(err(notFound())),
        );
        expect(fakes.biometricGate.prompts, equals(<BiometricReason>[]));
      });

      test('refuses an unknown resolution', () async {
        final (:useCase, fakes: _) = _setup();

        expect(
          await useCase.cast(_input(resolutionId: aResolutionId('missing'))),
          equals(
            err(
              ResolutionNotFoundError(resolutionId: aResolutionId('missing')),
            ),
          ),
        );
      });

      test(
        'refuses somebody who is not a participant of the meeting',
        () async {
          final (:fakes, :useCase) = _setup();
          fakes.auth.session = aSession(
            user: aSession().user.copyWith(id: aUserId('stranger')),
          );

          expect(
            await useCase.cast(_input()),
            equals(err(const NotAParticipantError())),
          );
        },
      );

      for (final role in [ParticipantRole.secretary, ParticipantRole.guest]) {
        test('refuses a ${role.value}, who has no voting rights', () async {
          final meeting = aMeeting(participants: [aParticipant(role: role)]);
          final (:fakes, :useCase) = _setup(meeting);

          expect(
            await useCase.cast(_input()),
            equals(err(const NoVotingRightsError())),
          );
          expect(fakes.votes.received, equals(<Vote>[]));
        });
      }

      test('refuses a closed resolution', () async {
        final (:useCase, fakes: _) = _setup(
          _meetingWith(aResolution(status: ResolutionStatus.closed)),
        );

        expect(
          await useCase.cast(_input()),
          equals(err(const ResolutionClosedError())),
        );
      });

      test('accepts a vote while the voting window is open, and refuses it '
          'once the clock reaches the end', () async {
        final (:fakes, :useCase) = _setup(
          _meetingWith(aResolution(closesAt: at(60000))),
        );
        fakes.clock.advance(59999);

        expect(
          await useCase.cast(_input()),
          equals(
            ok(
              CastVoteOutcome(
                status: CastVoteStatus.submitted,
                vote: aVote(castAt: at(59999)),
              ),
            ),
          ),
        );

        final late = _setup(_meetingWith(aResolution(closesAt: at(60000))));
        late.fakes.clock.advance(60000);
        expect(
          await late.useCase.cast(_input()),
          equals(err(const VotingWindowOverError())),
        );
        expect(late.fakes.votes.received, equals(<Vote>[]));
      });

      test('refuses a voter whose vote the server already records', () async {
        final (:fakes, :useCase) = _setup(
          _meetingWith(aResolution(recordedVote: VoteChoice.abstain)),
        );

        expect(
          await useCase.cast(_input()),
          equals(
            err(const AlreadyVotedError(source: AlreadyVotedSource.recorded)),
          ),
        );
        expect(fakes.biometricGate.prompts, equals(<BiometricReason>[]));
      });

      test('refuses a voter whose vote already waits in the outbox, and '
          'ignores the votes of others', () async {
        final (:fakes, :useCase) = _setup();
        fakes.outbox.seed([aPendingVote(aVote(voterId: aUserId('user-2')))]);

        expect(
          await useCase.cast(_input()),
          equals(
            ok(
              CastVoteOutcome(status: CastVoteStatus.submitted, vote: aVote()),
            ),
          ),
        );

        fakes.outbox.seed([aPendingVote(aVote())]);
        expect(
          await useCase.cast(_input()),
          equals(
            err(const AlreadyVotedError(source: AlreadyVotedSource.queued)),
          ),
        );
      });

      test(
        'returns the storage error when the outbox cannot be read',
        () async {
          final (:fakes, :useCase) = _setup();
          fakes.outbox.findFailure = storageReadFailed();

          expect(
            await useCase.cast(_input()),
            equals(err(storageReadFailed())),
          );
          expect(fakes.biometricGate.prompts, equals(<BiometricReason>[]));
        },
      );
    });

    group('the session after the biometric prompt', () {
      test('refuses the vote when another user signed in while the prompt '
          'was shown, and sends or queues nothing', () async {
        final (:fakes, :useCase) = _setup();
        fakes.biometricGate.onPrompt = () {
          fakes.auth.session = aSession(user: aUser(id: aUserId('user-2')));
        };

        expect(await useCase.cast(_input()), equals(err(sessionChanged())));
        expect(fakes.votes.received, equals(<Vote>[]));
        expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
      });

      test('refuses the vote when the app was locked while the prompt was '
          'shown', () async {
        final (:fakes, :useCase) = _setup();
        fakes.biometricGate.onPrompt = fakes.appLock.lock;

        expect(await useCase.cast(_input()), equals(err(appLocked())));
        expect(fakes.votes.received, equals(<Vote>[]));
      });

      test('refuses the vote when the session ended while the prompt was '
          'shown', () async {
        final (:fakes, :useCase) = _setup();
        fakes.biometricGate.onPrompt = () {
          fakes.auth.session = null;
        };

        expect(await useCase.cast(_input()), equals(err(notAuthenticated())));
        expect(fakes.votes.received, equals(<Vote>[]));
      });

      test('goes on when the same user is still signed in', () async {
        final (:fakes, :useCase) = _setup();
        fakes.biometricGate.onPrompt = () {
          fakes.auth.session = aSession();
        };

        final result = await useCase.cast(_input());

        expect(valueOf(result)?.status, equals(CastVoteStatus.submitted));
      });
    });

    group('the biometric confirmation', () {
      for (final error in [biometricCancelled(), biometricLockedOut()]) {
        test('stops the vote when the user ends with ${formatPretty(error)}: '
            'nothing is sent or queued', () async {
          final (:fakes, :useCase) = _setup();
          fakes.biometricGate.authentication = err(error);

          expect(await useCase.cast(_input()), equals(err(error)));
          expect(fakes.votes.received, equals(<Vote>[]));
          expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
        });
      }

      test('reports a device without biometrics, without a prompt', () async {
        final (:fakes, :useCase) = _setup();
        fakes.biometricGate.availability = err(biometricUnavailable());

        expect(
          await useCase.cast(_input()),
          equals(err(biometricUnavailable())),
        );
        expect(fakes.biometricGate.prompts, equals(<BiometricReason>[]));
        expect(fakes.votes.received, equals(<Vote>[]));
      });
    });

    group('a refusal of the server', () {
      for (final rejection in <VotingError>[
        const ResolutionClosedError(),
        const NotAParticipantError(),
        const AlreadyVotedError(source: AlreadyVotedSource.recorded),
      ]) {
        test('returns the business rejection ${formatPretty(rejection)}, '
            'queues nothing and logs it', () async {
          final (:fakes, :useCase) = _setup();
          fakes.votes.answerNext(err(rejection));

          expect(await useCase.cast(_input()), equals(err(rejection)));
          expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
          expect(
            fakes.monitoring.logs,
            equals([
              LogRecord(
                level: LogLevel.warn,
                event: MonitoringEvent.voteRejected,
                attributes: {
                  ..._voteAttributes(),
                  LogAttribute.errorCode: rejection.code,
                },
              ),
            ]),
          );
        });
      }

      test('returns unauthorized, and queues nothing: the user must sign in '
          'again', () async {
        final (:fakes, :useCase) = _setup();
        fakes.votes.answerNext(err(unauthorized()));

        expect(await useCase.cast(_input()), equals(err(unauthorized())));
        expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
        expect(fakes.monitoring.logs, equals(<LogRecord>[]));
      });

      test('ends the session on the device: the user is signed out, the app '
          'locked, the caches emptied', () async {
        final (:fakes, :useCase) = _setup();
        fakes.votes.answerNext(err(unauthorized()));

        await useCase.cast(_input());

        expect(fakes.auth.signOutCalls, equals(1));
        expect(fakes.auth.session, isNull);
        expect(fakes.appLock.isLocked(), isTrue);
        expect(fakes.meetingCache.isEmpty(), isTrue);
      });

      test('does not sign out somebody else who signed in meanwhile: that '
          'session was not refused', () async {
        final (:fakes, :useCase) = _setup();
        fakes.votes.onReceive = (_) {
          fakes.auth.session = aSession(user: aUser(id: aUserId('user-2')));
        };
        fakes.votes.answerNext(err(unauthorized()));

        expect(await useCase.cast(_input()), equals(err(unauthorized())));

        expect(fakes.auth.signOutCalls, equals(0));
        expect(fakes.auth.session?.user.id, equals(aUserId('user-2')));
        expect(fakes.appLock.isLocked(), isFalse);
      });

      test('captures a session that cannot be forgotten, and still returns '
          'unauthorized', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.signOutFailure = storageWriteFailed();
        fakes.votes.answerNext(err(unauthorized()));

        expect(await useCase.cast(_input()), equals(err(unauthorized())));
        expect(
          fakes.monitoring.capturedEvents(),
          equals([MonitoringEvent.signOutFailed]),
        );
      });
    });

    group('an entry of the outbox that cannot be read holds the key of the '
        'vote', () {
      test('does not overwrite it, queues nothing, and says the vote could '
          'not be stored', () async {
        final (:fakes, :useCase) = _setup();
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
        fakes.network.goOffline();
        fakes.outbox.seedUnreadable(
          aUserId(),
          idempotencyKeyOf(aResolutionId(), aUserId()),
        );

        final result = await useCase.cast(_input());

        expect(
          result,
          equals(err(storageWriteFailed('unreadable entry holds the key'))),
        );
        expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
        expect(fakes.outbox.unreadableSnapshot(), hasLength(1));
        expect(
          fakes.monitoring.capturedEvents(),
          equals([MonitoringEvent.voteEnqueueFailed]),
        );
      });

      test('queues the vote once the entry is discarded', () async {
        final (:fakes, :useCase) = _setup();
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
        fakes.network.goOffline();
        fakes.outbox.seedUnreadable(
          aUserId(),
          idempotencyKeyOf(aResolutionId(), aUserId()),
        );
        await useCase.cast(_input());
        await fakes.outbox.discardUnreadable(aUserId());

        final result = await useCase.cast(_input());

        expect(valueOf(result)?.status, equals(CastVoteStatus.queued));
      });
    });

    group('an unexpected failure of the server', () {
      test('queues the vote like a network failure, since the server may '
          'have recorded it, and counts an attempt', () async {
        final (:fakes, :useCase) = _setup();
        fakes.votes.answerNext(err(unexpected('HTTP 500')));

        final result = await useCase.cast(_input());

        expect(valueOf(result)?.status, equals(CastVoteStatus.queued));
        expect(
          fakes.outbox.snapshot(),
          equals([PendingVote(vote: aVote(), enqueuedAt: now, attempts: 1)]),
        );
      });

      test('captures the failure it swallows, and logs the vote as '
          'queued', () async {
        final (:fakes, :useCase) = _setup();
        fakes.votes.answerNext(err(unexpected('HTTP 500')));

        await useCase.cast(_input());

        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.voteSubmitFailed,
              error: unexpected('HTTP 500'),
              attributes: _voteAttributes(),
            ),
          ]),
        );
        expect(
          fakes.monitoring.loggedEvents(),
          equals([MonitoringEvent.voteQueued]),
        );
      });

      test('is replayed safely: the server holds the vote once if it had '
          'recorded it', () async {
        final (:fakes, :useCase) = _setup();
        fakes.votes.answerNext(err(unexpected('answer lost')));
        await useCase.cast(_input());

        final queued = fakes.outbox.snapshot().firstOrNull;
        if (queued == null) {
          throw StateError('the vote should be queued');
        }
        await fakes.votes.submit(queued.vote);
        await fakes.votes.submit(queued.vote);

        expect(fakes.votes.recordedVotes(), equals([queued.vote]));
      });
    });

    group('a failure of the outbox', () {
      test('is captured with a dedicated event before it is returned, when '
          'the vote could not be kept', () async {
        final (:fakes, :useCase) = _setup();
        fakes.votes.answerNext(err(networkUnavailable()));
        fakes.outbox.enqueueFailure = storageWriteFailed('disk full');

        expect(
          await useCase.cast(_input()),
          equals(err(storageWriteFailed('disk full'))),
        );
        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.voteEnqueueFailed,
              error: storageWriteFailed('disk full'),
              attributes: _voteAttributes(),
            ),
          ]),
        );
      });
    });

    group('the cached meeting after a vote the server recorded', () {
      test('records the vote, so that the copy shows it', () async {
        final (:fakes, :useCase) = _setup();

        await useCase.cast(_input(choice: VoteChoice.against));

        expect(await _cachedChoice(fakes), equals(VoteChoice.against));
      });

      test('keeps the date the copy was cached at', () async {
        final (:fakes, :useCase) = _setup();
        await useCase.cast(_input());
        fakes.clock.advance(60000);
        fakes.network.goOffline();

        final cached = await fakes.meetingCache.readMeeting(
          aUserId(),
          aMeetingId(),
        );
        expect(valueOf(cached)?.cachedAt, equals(now));
      });

      test('stops the user from voting again offline: told it was already '
          'voted, not "queued"', () async {
        final (:fakes, :useCase) = _setup();
        await useCase.cast(_input());
        fakes.network.goOffline();
        fakes.biometricGate.prompts.clear();

        final second = await useCase.cast(_input(choice: VoteChoice.against));

        expect(
          second,
          equals(
            err(const AlreadyVotedError(source: AlreadyVotedSource.recorded)),
          ),
        );
        expect(fakes.biometricGate.prompts, equals(<BiometricReason>[]));
        expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
      });

      test('does not fail the vote when the copy cannot be updated, and '
          'captures it', () async {
        final (:fakes, :useCase) = _setup();
        // The meeting is cached when it is loaded; the cache breaks while the
        // vote is sent.
        fakes.votes.onReceive = (_) {
          fakes.meetingCache.writeFailure = storageWriteFailed();
        };

        final result = await useCase.cast(_input());

        expect(valueOf(result)?.status, equals(CastVoteStatus.submitted));
        expect(fakes.monitoring.errors, [
          isA<ErrorRecord>()
              .having(
                (record) => record.event,
                'event',
                MonitoringEvent.cacheWriteFailed,
              )
              .having(
                (record) => record.error,
                'error',
                equals(storageWriteFailed()),
              ),
        ]);
      });

      test('does not write it for a vote that was only queued', () async {
        final (:fakes, :useCase) = _setup();
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
        fakes.network.goOffline();

        await useCase.cast(_input());

        expect(await _cachedChoice(fakes), isNull);
      });
    });

    group('two votes on the same resolution at the same time', () {
      test('fails the second one at once with a precise error, and the first '
          'one goes through', () async {
        final (:fakes, :useCase) = _setup();

        final [first, second] = await Future.wait([
          useCase.cast(_input()),
          useCase.cast(_input(choice: VoteChoice.against)),
        ]);

        expect(valueOf(first)?.status, equals(CastVoteStatus.submitted));
        expect(second, equals(err(voteInProgress())));
        expect(fakes.biometricGate.prompts, hasLength(1));
        expect(
          fakes.votes.recordedVotes().map((vote) => vote.choice).toList(),
          equals([VoteChoice.forChoice]),
        );
      });

      test('lets a vote on another resolution proceed', () async {
        final (:useCase, fakes: _) = _setup(
          aMeeting(
            agenda: [
              anAgendaItem(),
              anAgendaItem(
                id: anAgendaItemId('agenda-2'),
                position: 2,
                resolution: aResolution(id: aResolutionId('resolution-2')),
              ),
            ],
          ),
        );

        final [first, second] = await Future.wait([
          useCase.cast(_input()),
          useCase.cast(_input(resolutionId: aResolutionId('resolution-2'))),
        ]);

        expect(
          first,
          equals(
            ok(
              CastVoteOutcome(status: CastVoteStatus.submitted, vote: aVote()),
            ),
          ),
        );
        expect(
          second,
          equals(
            ok(
              CastVoteOutcome(
                status: CastVoteStatus.submitted,
                vote: aVote(resolutionId: aResolutionId('resolution-2')),
              ),
            ),
          ),
        );
      });

      test('accepts a new attempt as soon as the previous one is over, '
          'whatever its outcome', () async {
        final (:fakes, :useCase) = _setup();
        fakes.biometricGate.authentication = err(biometricCancelled());
        expect(await useCase.cast(_input()), equals(err(biometricCancelled())));

        fakes.biometricGate.authentication = ok<void>(null);

        expect(
          await useCase.cast(_input()),
          equals(
            ok(
              CastVoteOutcome(status: CastVoteStatus.submitted, vote: aVote()),
            ),
          ),
        );
      });

      test('is refused by the outbox, not hidden, when two instances queue '
          'different choices at once', () async {
        final first = _setup();
        final second = CastVote(first.fakes);
        await first.fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
        first.fakes.network.goOffline();

        final [a, b] = await Future.wait([
          first.useCase.cast(_input()),
          second.cast(_input(choice: VoteChoice.against)),
        ]);

        expect(valueOf(a)?.status, equals(CastVoteStatus.queued));
        expect(
          b,
          equals(
            err(const AlreadyVotedError(source: AlreadyVotedSource.queued)),
          ),
        );
        expect(
          first.fakes.outbox
              .snapshot()
              .map((entry) => entry.vote.choice)
              .toList(),
          equals([VoteChoice.forChoice]),
        );
      });
    });

    group('a vote of the user that the outbox holds as rejected', () {
      test('is not replaced by a new one: the user must acknowledge it '
          'first', () async {
        final (:fakes, :useCase) = _setup();
        final rejected = aRejectedVote(aVote(), voteUndeliverable(5));
        fakes.outbox.seed([rejected]);

        expect(
          await useCase.cast(_input()),
          equals(err(votePreviouslyRejected(voteUndeliverable(5)))),
        );
        expect(fakes.biometricGate.prompts, equals(<BiometricReason>[]));
        expect(fakes.votes.received, equals(<Vote>[]));
        expect(fakes.outbox.snapshot(), equals([rejected]));
      });

      test('is reported when the outbox refuses the new vote because of '
          'it', () async {
        final fakes = createFakes();
        fakes.meetings.addMeeting(aMeeting());
        final outbox = _BlindOutbox()
          ..seed([
            // The reason is part of the scenario: it is spelled out.
            // ignore: avoid_redundant_argument_values
            aRejectedVote(aVote(), const ResolutionClosedError()),
          ]);

        fakes.votes.answerNext(err(networkUnavailable()));

        final result = await CastVote(VotesDeps(fakes, outbox: outbox))
            .cast(_input());

        expect(
          result,
          equals(err(votePreviouslyRejected(const ResolutionClosedError()))),
        );
      });

      test('is not mixed up with the votes of another user', () async {
        final (:fakes, :useCase) = _setup();
        final others = aRejectedVote(aVote(voterId: aUserId('user-2')));
        fakes.outbox.seed([others]);

        expect(
          await useCase.cast(_input()),
          equals(
            ok(
              CastVoteOutcome(status: CastVoteStatus.submitted, vote: aVote()),
            ),
          ),
        );
        expect(fakes.outbox.snapshot(), equals([others]));
      });
    });

    group('the instants of a vote', () {
      test('keeps the instant of the cast in the vote and takes the instant '
          'of the enqueueing from the clock at that moment', () async {
        final (:fakes, :useCase) = _setup();
        fakes.clock.advance(1000);
        // The biometric prompt is long gone and the request takes its time: the
        // clock moves on.
        fakes.votes.onReceive = (_) => fakes.clock.advance(7000);
        fakes.votes.answerNext(err(networkUnavailable()));

        await useCase.cast(_input());

        expect(
          fakes.outbox.snapshot(),
          equals([
            PendingVote(
              vote: aVote(castAt: at(1000)),
              enqueuedAt: at(8000),
              attempts: 0,
            ),
          ]),
        );
      });

      test('stamps the vote after the biometric confirmation, not '
          'before', () async {
        final fakes = createFakes();
        fakes.meetings.addMeeting(aMeeting());
        fakes.biometricGate.authentication = ok<void>(null);
        final useCase = CastVote(
          VotesDeps(
            fakes,
            biometricGate: _SlowGate(fakes.biometricGate, fakes.clock, 4000),
          ),
        );

        final result = await useCase.cast(_input());

        expect(valueOf(result)?.vote.castAt, equals(at(4000)));
      });
    });

    group('a resolution that sits in a later item of the agenda', () {
      final second = _input(resolutionId: aResolutionId('resolution-2'));

      test('can be voted on, and only that resolution is recorded in the '
          'cached meeting', () async {
        final (:fakes, :useCase) = _setup(aMeetingWithAgenda());

        final result = await useCase.cast(
          _input(resolutionId: second.resolutionId, choice: VoteChoice.abstain),
        );

        expect(
          result,
          equals(
            ok(
              CastVoteOutcome(
                status: CastVoteStatus.submitted,
                vote: aVote(
                  resolutionId: aResolutionId('resolution-2'),
                  choice: VoteChoice.abstain,
                ),
              ),
            ),
          ),
        );
        final cached = await fakes.meetingCache.readMeeting(
          aUserId(),
          aMeetingId(),
        );
        final meeting = valueOf(cached)?.value;
        expect(meeting, isNotNull);
        expect(
          meeting == null
              ? null
              : findResolution(
                  meeting,
                  aResolutionId('resolution-2'),
                )?.recordedVote,
          equals(VoteChoice.abstain),
        );
        final firstResolution = meeting == null
            ? null
            : findResolution(meeting, aResolutionId());
        expect(firstResolution, isNotNull);
        expect(firstResolution?.recordedVote, isNull);
      });

      test('is refused when it is closed, even though the first resolution '
          'is open', () async {
        final closed = anAgendaItem(
          id: anAgendaItemId('agenda-2'),
          position: 2,
          resolution: aResolution(
            id: aResolutionId('resolution-2'),
            status: ResolutionStatus.closed,
          ),
        );
        final (:useCase, fakes: _) = _setup(
          aMeeting(agenda: [anAgendaItem(), closed]),
        );

        expect(
          await useCase.cast(second),
          equals(err(const ResolutionClosedError())),
        );
        expect(
          await useCase.cast(_input()),
          equals(
            ok(
              CastVoteOutcome(status: CastVoteStatus.submitted, vote: aVote()),
            ),
          ),
        );
      });

      test('is refused when the meeting has no such resolution in any '
          'item', () async {
        final (:useCase, fakes: _) = _setup(aMeetingWithAgenda());

        expect(
          await useCase.cast(
            _input(resolutionId: aResolutionId('resolution-3')),
          ),
          equals(
            err(
              ResolutionNotFoundError(
                resolutionId: aResolutionId('resolution-3'),
              ),
            ),
          ),
        );
      });
    });

    group('when the meeting cannot be loaded from the server although a copy '
        'is cached', () {
      final failures = <(String, GatewayError)>[
        ('unauthorized', unauthorized()),
        ('an unexpected failure', unexpected('HTTP 500')),
      ];
      for (final (name, failure) in failures) {
        test('does not vote on the cached copy: $name', () async {
          final (:fakes, :useCase) = _setup();
          await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
          fakes.meetings.failure = failure;

          expect(await useCase.cast(_input()), equals(err(failure)));
          expect(fakes.biometricGate.prompts, equals(<BiometricReason>[]));
          expect(fakes.votes.received, equals(<Vote>[]));
          expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
        });
      }

      test('evicts the cached copy when the server refuses the user', () async {
        final (:fakes, :useCase) = _setup();
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
        fakes.meetings.failure = unauthorized();

        await useCase.cast(_input());

        expect(
          await fakes.meetingCache.readMeeting(aUserId(), aMeetingId()),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );
      });

      test(
        'leaves the cached copy when the server fails unexpectedly',
        () async {
          final (:fakes, :useCase) = _setup();
          await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
          fakes.meetings.failure = unexpected('HTTP 500');

          await useCase.cast(_input());

          expect(
            await fakes.meetingCache.readMeeting(aUserId(), aMeetingId()),
            equals(ok(CacheEntry(value: aMeeting(), cachedAt: now))),
          );
        },
      );
    });
  });
}
