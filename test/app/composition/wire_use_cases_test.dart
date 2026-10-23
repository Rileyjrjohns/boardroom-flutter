import 'package:boardroom/app/composition/ports.dart';
import 'package:boardroom/app/composition/use_cases.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/votes/application/use_cases/sync_pending_votes.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:test/test.dart';

import '../../support/builders/builders.dart';
import '../../support/fakes/create_fakes.dart';

// The scenarios of `wireUseCases.test.ts`: the wiring over the ports of the
// fakes, as a configuration would build them.

final UseCaseSettings _settings = UseCaseSettings(
  maxCacheAge: aDuration(10 * millisPerMinute),
  maxAttempts: 2,
  gracePeriod: aDuration(millisPerMinute),
  startsLocked: false,
);

/// The fakes, as the ports a configuration would build.
Ports _portsOf(Fakes fakes) => Ports(
  clock: fakes.clock,
  monitoring: fakes.monitoring,
  auth: fakes.auth,
  biometricGate: fakes.biometricGate,
  connectivity: fakes.connectivity,
  screenProtection: fakes.screenProtection,
  meetings: fakes.meetings,
  meetingCache: fakes.meetingCache,
  documents: fakes.documents,
  documentCache: fakes.documentCache,
  votes: fakes.votes,
  outbox: fakes.outbox,
);

({Fakes fakes, UseCases useCases}) _wired([UseCaseSettings? settings]) {
  final fakes = createFakes();
  return (
    fakes: fakes,
    useCases: wireUseCases(_portsOf(fakes), settings ?? _settings),
  );
}

PageRequest _firstPage() => unwrap(createPageRequest(limit: 5));

bool _isOk(Result<Object?, Object?> result) => result is Ok;

void main() {
  group('wireUseCases', () {
    test('builds every use case, each one working on the ports it was '
        'given', () async {
      final (:fakes, :useCases) = _wired();
      fakes.meetings.addMeeting(aMeeting());

      expect(
        _isOk(await useCases.getMeeting.execute(meetingId: aMeetingId())),
        isTrue,
      );
      expect(
        _isOk(
          await useCases.listMeetings.execute(
            period: MeetingPeriod.upcoming,
            request: _firstPage(),
          ),
        ),
        isTrue,
      );
      expect(_isOk(await useCases.unlockApp.execute()), isTrue);
      expect(_isOk(await useCases.listPendingVotes.execute()), isTrue);
      expect(_isOk(await useCases.syncPendingVotes.execute()), isTrue);
      expect(_isOk(await useCases.restoreSession.execute()), isTrue);
      expect(
        _isOk(await useCases.evaluateAppLock.execute(backgroundedAt: now)),
        isTrue,
      );
      expect(_isOk(await useCases.signOut.execute()), isTrue);
      expect(fakes.auth.signOutCalls, equals(1));
    });

    test('hands out the same instance every time it is read, so that guards '
        'in memory hold', () async {
      final (:fakes, :useCases) = _wired();
      fakes.meetings.addMeeting(aMeeting());
      final vote = aVote();

      final first = useCases.castVote.execute(
        meetingId: aMeetingId(),
        resolutionId: vote.resolutionId,
        choice: vote.choice,
      );
      final second = useCases.castVote.execute(
        meetingId: aMeetingId(),
        resolutionId: vote.resolutionId,
        choice: vote.choice,
      );

      expect(await second, equals(err(voteInProgress())));
      expect(_isOk(await first), isTrue);
    });

    test('shares one SyncPendingVotes: a second call during a run does '
        'nothing', () async {
      final (:fakes, :useCases) = _wired();
      await fakes.outbox.enqueue(aPendingVote());

      final first = useCases.syncPendingVotes.execute();
      final second = useCases.syncPendingVotes.execute();

      expect(await second, equals(ok(const SyncAlreadyRunning())));
      expect(_isOk(await first), isTrue);
      expect(fakes.votes.received, hasLength(1));
    });

    test('shares one ScreenProtectionCoordinator between opening and closing '
        'documents', () async {
      final (:fakes, :useCases) = _wired();
      final first = aConfidentialDocument(id: aDocumentId());
      final second = aConfidentialDocument(id: aDocumentId('document-2'));
      fakes.documents
        ..addDocument(first, aDocumentLocation('file:///documents/1.pdf'))
        ..addDocument(second, aDocumentLocation('file:///documents/2.pdf'));
      await useCases.openDocument.execute(documentId: first.id);
      await useCases.openDocument.execute(documentId: second.id);
      expect(fakes.screenProtection.enabled, isTrue);

      await useCases.closeDocument.execute(documentId: first.id);
      expect(fakes.screenProtection.enabled, isTrue);

      await useCases.closeDocument.execute(documentId: second.id);
      expect(fakes.screenProtection.enabled, isFalse);
    });

    test('forwards the maximum age of the cache: older than it, an entry is '
        'not served offline', () async {
      final (:fakes, :useCases) = _wired();
      fakes.meetings.addMeeting(aMeeting());
      await useCases.getMeeting.execute(meetingId: aMeetingId());
      fakes.network.goOffline();

      fakes.clock.advance(10 * millisPerMinute);
      final withinAge = await useCases.getMeeting.execute(
        meetingId: aMeetingId(),
      );
      fakes.clock.advance(1);
      final tooOld = await useCases.getMeeting.execute(meetingId: aMeetingId());

      expect(_isOk(withinAge), isTrue);
      expect(tooOld, isA<Err<Object?, Object?>>());
    });

    test('forwards the maximum number of attempts: a vote is given up after '
        'that many unexpected failures', () async {
      final (:fakes, :useCases) = _wired();
      await fakes.outbox.enqueue(aPendingVote(aVote(), at(0)));
      fakes.votes
        ..answerNext(err(unexpected()))
        ..answerNext(err(unexpected()));

      await useCases.syncPendingVotes.execute();
      expect(
        fakes.outbox.snapshot().first.status,
        equals(OutboxStatus.pending),
      );
      await useCases.syncPendingVotes.execute();

      expect(
        fakes.outbox.snapshot().first.status,
        equals(OutboxStatus.rejected),
      );
    });

    test('forwards the grace period of the app lock', () async {
      final (:fakes, :useCases) = _wired();
      fakes.clock.advance(millisPerMinute - 1);
      final before = await useCases.evaluateAppLock.execute(
        backgroundedAt: now,
      );
      fakes.clock.advance(1);
      final after = await useCases.evaluateAppLock.execute(backgroundedAt: now);

      expect(before, equals(ok(false)));
      expect(after, equals(ok(true)));
    });

    test('builds a new set every time: nothing is shared between two '
        'calls', () {
      final fakes = createFakes();
      final first = wireUseCases(_portsOf(fakes), _settings);
      final second = wireUseCases(_portsOf(fakes), _settings);

      expect(first.castVote, isNot(same(second.castVote)));
      expect(first.syncPendingVotes, isNot(same(second.syncPendingVotes)));
      expect(first.listMeetings, isNot(same(second.listMeetings)));
    });

    group('the lock of the app', () {
      UseCaseSettings withLock({required bool startsLocked}) => UseCaseSettings(
        maxCacheAge: _settings.maxCacheAge,
        maxAttempts: _settings.maxAttempts,
        gracePeriod: _settings.gracePeriod,
        startsLocked: startsLocked,
      );

      test('is built open or closed as the settings say', () async {
        final fakes = createFakes();
        fakes.meetings.addMeeting(aMeeting());
        final open = wireUseCases(
          _portsOf(fakes),
          withLock(startsLocked: false),
        );
        final closed = wireUseCases(
          _portsOf(fakes),
          withLock(startsLocked: true),
        );

        expect(
          _isOk(await open.getMeeting.execute(meetingId: aMeetingId())),
          isTrue,
        );
        expect(
          await closed.getMeeting.execute(meetingId: aMeetingId()),
          equals(err(appLocked())),
        );
      });

      test('is one state shared by every use case: the unlock of one opens '
          'them all', () async {
        final fakes = createFakes();
        fakes.meetings.addMeeting(aMeeting());
        final useCases = wireUseCases(
          _portsOf(fakes),
          withLock(startsLocked: true),
        );
        Future<Result<Object?, AppError>> listed() => useCases.listMeetings
            .execute(period: MeetingPeriod.upcoming, request: _firstPage());
        expect(await listed(), equals(err(appLocked())));
        expect(
          await useCases.listPendingVotes.execute(),
          equals(err(appLocked())),
        );

        await useCases.unlockApp.execute();

        expect(_isOk(await listed()), isTrue);
        expect(
          _isOk(await useCases.getMeeting.execute(meetingId: aMeetingId())),
          isTrue,
        );
        expect(_isOk(await useCases.listPendingVotes.execute()), isTrue);
      });

      test('is closed again by the restore of a session, the lock of the '
          'grace period and the sign-out', () async {
        final fakes = createFakes();
        final useCases = wireUseCases(
          _portsOf(fakes),
          withLock(startsLocked: false),
        );
        Future<bool> isOpen() async =>
            _isOk(await useCases.listPendingVotes.execute());
        expect(await isOpen(), isTrue);

        await useCases.restoreSession.execute();
        expect(await isOpen(), isFalse);

        await useCases.unlockApp.execute();
        fakes.clock.advance(_settings.gracePeriod);
        await useCases.evaluateAppLock.execute(backgroundedAt: now);
        expect(await isOpen(), isFalse);

        await useCases.unlockApp.execute();
        expect(await isOpen(), isTrue);
        await useCases.signOut.execute();
        fakes.auth.session = aSession();
        expect(await isOpen(), isFalse);
      });
    });
  });
}
