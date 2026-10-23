// The arguments restate the values of the scenario, even when they are the
// defaults of the builders.
// ignore_for_file: avoid_redundant_argument_values

import 'dart:async';

import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/page.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/features/auth/application/ports/auth_session.dart';
import 'package:boardroom/features/auth/application/session/app_lock.dart';
import 'package:boardroom/features/auth/application/use_cases/evaluate_app_lock.dart';
import 'package:boardroom/features/auth/application/use_cases/restore_session.dart';
import 'package:boardroom/features/auth/application/use_cases/sign_in.dart';
import 'package:boardroom/features/auth/application/use_cases/sign_out.dart';
import 'package:boardroom/features/auth/application/use_cases/unlock_app.dart';
import 'package:boardroom/features/auth/domain/entities/user.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/application/use_cases/close_document.dart';
import 'package:boardroom/features/documents/application/use_cases/observe_screen_capture.dart';
import 'package:boardroom/features/documents/application/use_cases/open_document.dart';
import 'package:boardroom/features/documents/domain/value_objects/watermark.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';
import 'package:boardroom/features/meetings/application/use_cases/get_meeting.dart';
import 'package:boardroom/features/meetings/application/use_cases/list_meetings.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/use_cases/cast_vote.dart';
import 'package:boardroom/features/votes/application/use_cases/list_pending_votes.dart';
import 'package:boardroom/features/votes/application/use_cases/sync_pending_votes.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:test/test.dart';

import '../../support/builders/builders.dart';
import '../../support/fakes/create_fakes.dart';

// The security weaknesses found by the independent re-check of the domain and
// the application, each reproduced as a scenario through the use cases, with
// the fakes of the ports. A scenario failed before its fix; together they are
// the regression suite of the fixes.

final User _alice = aUser();
final User _bruno = aUser(
  id: aUserId('user-2'),
  fullName: 'Bruno Durand',
  email: anEmail('bruno@example.com'),
);
const String _brunoPassword = 'bruno-secret';

/// The fakes, with a second account that can sign in.
Fakes _world() {
  final fakes = createFakes();
  fakes.auth.registerAccount(
    _bruno.email,
    _brunoPassword,
    aSession(user: _bruno),
  );
  return fakes;
}

Future<Result<Object?, Object?>> _signInAsBruno(Fakes fakes) =>
    SignIn(fakes).execute(email: _bruno.email, password: _brunoPassword);

final Meeting _meeting = aMeeting();
final MeetingId _otherMeetingId = aMeetingId('meeting-2');
final PageRequest _firstPage = unwrap(createPageRequest(limit: 20));
const MeetingPageKey _pageKey = MeetingPageKey(
  period: MeetingPeriod.upcoming,
  limit: 20,
);
final ViewableDocument _viewable = ViewableDocument(
  document: aDocument(),
  location: aDocumentLocation(),
);

/// Lets the work that a callback started in the background finish.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Whether the opening succeeded and screen protection was on: `false` when it
/// failed, as `opened.ok && opened.value.screenProtected` is in TypeScript.
bool _screenProtected(Result<OpenedDocument, Object?> opened) =>
    switch (opened) {
      Ok(:final value) => value.screenProtected,
      Err() => false,
    };

/// Whether the read succeeded and found an entry.
bool _isCached(Result<Object?, Object?> read) => switch (read) {
  Ok(:final value) => value != null,
  Err() => false,
};

/// The fakes as the deps of `EvaluateAppLock`, with a grace period of their
/// own: `{ ...fakes, gracePeriod }` in TypeScript.
final class _WithGracePeriod implements EvaluateAppLockDeps {
  const new(this._fakes, this.gracePeriod);

  final Fakes _fakes;

  @override
  final DurationMillis gracePeriod;

  @override
  AuthSession get auth => _fakes.auth;

  @override
  Clock get clock => _fakes.clock;

  @override
  AppLock get appLock => _fakes.appLock;
}

void main() {
  group('F1: the app lock is enforced, not only returned', () {
    test('locks every read after a cold start, '
        'and RestoreSession gives away no identity', () async {
      final fakes = _world();
      fakes.meetings.addMeeting(_meeting);

      final restored = await RestoreSession(fakes).execute();

      expect(unwrap(restored).status, equals(SessionRestore.unlockRequired));
      expect('$restored', isNot(contains(_alice.fullName)));
      expect('$restored', isNot(contains(_alice.email)));
      expect(
        await GetMeeting(fakes).execute(meetingId: _meeting.id),
        equals(err(appLocked())),
      );
      expect(
        await ListMeetings(fakes)
            .execute(period: MeetingPeriod.upcoming, request: _firstPage),
        equals(err(appLocked())),
      );
      expect(fakes.meetings.getCalls, isEmpty);
    });

    test('locks everything else too: '
        'documents, votes, the outbox and its synchronisation', () async {
      final fakes = _world();
      fakes.meetings.addMeeting(_meeting);
      fakes.documents.addDocument(aDocument(), aDocumentLocation());
      fakes.outbox.seed([aPendingVote()]);
      await RestoreSession(fakes).execute();

      final results = <Object>[
        await OpenDocument(fakes).execute(documentId: aDocument().id),
        await CastVote(fakes).execute(
          meetingId: _meeting.id,
          resolutionId: aResolutionId(),
          choice: VoteChoice.forChoice,
        ),
        await ListPendingVotes(fakes).execute(),
        await SyncPendingVotes(fakes).execute(),
      ];

      expect(results, equals(results.map((_) => err(appLocked())).toList()));
      expect(fakes.votes.received, isEmpty);
      expect(fakes.screenProtection.enableCalls, equals(0));
      expect(fakes.outbox.snapshot(), equals([aPendingVote()]));
    });

    test('opens again when the biometrics succeed, '
        'and stays closed when they do not', () async {
      final fakes = _world();
      fakes.meetings.addMeeting(_meeting);
      await RestoreSession(fakes).execute();
      fakes.biometricGate.authentication = err(biometricFailed());

      await UnlockApp(fakes).execute();
      expect(
        await GetMeeting(fakes).execute(meetingId: _meeting.id),
        equals(err(appLocked())),
      );

      fakes.biometricGate.authentication = ok<void>(null);
      await UnlockApp(fakes).execute();
      expect(
        isOk(await GetMeeting(fakes).execute(meetingId: _meeting.id)),
        isTrue,
      );
    });

    test('locks when the grace period in the background is over, '
        'and not before', () async {
      final fakes = _world();
      fakes.meetings.addMeeting(_meeting);
      final evaluate = EvaluateAppLock(
        _WithGracePeriod(fakes, aDuration(60000)),
      );

      fakes.clock.advance(59999);
      expect(await evaluate.execute(backgroundedAt: now), equals(ok(false)));
      expect(
        isOk(await GetMeeting(fakes).execute(meetingId: _meeting.id)),
        isTrue,
      );

      fakes.clock.advance(1);
      expect(await evaluate.execute(backgroundedAt: now), equals(ok(true)));
      expect(
        await GetMeeting(fakes).execute(meetingId: _meeting.id),
        equals(err(appLocked())),
      );
    });

    test('leaves the app unlocked after a sign-in, '
        'and locked after a sign-out', () async {
      final fakes = _world();
      fakes.meetings.addMeeting(_meeting);
      await RestoreSession(fakes).execute();

      await _signInAsBruno(fakes);
      expect(
        isOk(await GetMeeting(fakes).execute(meetingId: _meeting.id)),
        isTrue,
      );

      await SignOut(fakes).execute();
      fakes.auth.session = aSession();
      expect(
        await GetMeeting(fakes).execute(meetingId: _meeting.id),
        equals(err(appLocked())),
      );
    });

    test('answers that nobody is signed in '
        'before it answers that the app is locked', () async {
      final fakes = _world();
      await RestoreSession(fakes).execute();
      fakes.auth.session = null;

      expect(
        await GetMeeting(fakes).execute(meetingId: _meeting.id),
        equals(err(notAuthenticated())),
      );
    });
  });

  group('F2: a document served from the cache '
      'is always opened with the screen protected', () {
    test('protects a document cached as public '
        'and reclassified confidential since', () async {
      final fakes = _world();
      final cached = aDocument(confidentiality: ConfidentialityLevel.public);
      await fakes.documentCache.save(
        _alice.id,
        ViewableDocument(document: cached, location: _viewable.location),
        now,
      );
      fakes.network.goOffline();

      final opened = await OpenDocument(fakes).execute(documentId: cached.id);

      expect(_screenProtected(opened), isTrue);
      expect(fakes.screenProtection.enabled, isTrue);
    });

    test('protects any stale document, whatever its cached level', () async {
      for (final level in ConfidentialityLevel.values) {
        final fakes = _world();
        final cached = aDocument(confidentiality: level);
        await fakes.documentCache.save(
          _alice.id,
          ViewableDocument(document: cached, location: _viewable.location),
          now,
        );
        fakes.network.goOffline();

        final opened = await OpenDocument(fakes).execute(documentId: cached.id);

        expect(_screenProtected(opened), isTrue);
      }
    });

    test('does not serve an old entry '
        'that a failed write-through left behind', () async {
      final fakes = _world();
      final old = aDocument(confidentiality: ConfidentialityLevel.public);
      await fakes.documentCache.save(
        _alice.id,
        ViewableDocument(document: old, location: _viewable.location),
        now,
      );
      fakes.documents.addDocument(
        aConfidentialDocument(id: old.id),
        _viewable.location,
      );
      fakes.documentCache.writeFailure = storageWriteFailed();
      final online = await OpenDocument(fakes).execute(documentId: old.id);
      fakes.documentCache.writeFailure = null;
      fakes.network.goOffline();

      final offline = await OpenDocument(fakes).execute(documentId: old.id);

      expect(_screenProtected(online), isTrue);
      expect(offline, equals(err(networkUnavailable())));
    });

    test('leaves a fresh public document unprotected: '
        'only what came from the cache is suspect', () async {
      final fakes = _world();
      fakes.documents.addDocument(aDocument(), _viewable.location);

      final opened = await OpenDocument(fakes)
          .execute(documentId: aDocument().id);

      expect(_screenProtected(opened), isFalse);
      expect(fakes.screenProtection.enableCalls, equals(0));
    });
  });

  group('F3: a revocation empties what hangs off the item, '
      'and a failed eviction empties everything', () {
    Future<({Meeting other, Document otherDocument})> fillCaches(
      Fakes fakes,
    ) async {
      final other = aMeeting(summary: aMeetingSummary(id: _otherMeetingId));
      final otherDocument = aDocument(id: aDocumentId('document-9'));
      await fakes.meetingCache.saveMeeting(_alice.id, _meeting, now);
      await fakes.meetingCache.saveMeeting(_alice.id, other, now);
      await fakes.meetingCache.savePage(
        _alice.id,
        _pageKey,
        createPage([aMeetingSummary()]),
        now,
      );
      await fakes.documentCache.save(
        _alice.id,
        ViewableDocument(document: aDocument(), location: _viewable.location),
        now,
      );
      await fakes.documentCache.save(
        _alice.id,
        ViewableDocument(
          document: otherDocument,
          location: aDocumentLocation('file:///documents/9.pdf'),
        ),
        now,
      );
      return (other: other, otherDocument: otherDocument);
    }

    test('empties both caches, for everyone, '
        'when the session is refused', () async {
      final fakes = _world();
      await fillCaches(fakes);
      await fakes.meetingCache.saveMeeting(_bruno.id, _meeting, now);
      fakes.meetings.failure = unauthorized();

      final result = await GetMeeting(fakes).execute(meetingId: _meeting.id);

      expect(result, equals(err(unauthorized())));
      expect(fakes.meetingCache.isEmpty(), isTrue);
      expect(fakes.documentCache.isEmpty(), isTrue);
    });

    test('empties both caches too '
        'when the session is refused on a document or on a list', () async {
      final onDocument = _world();
      await fillCaches(onDocument);
      onDocument.documents.failure = unauthorized();
      await OpenDocument(onDocument).execute(documentId: aDocument().id);
      final onList = _world();
      await fillCaches(onList);
      onList.meetings.failure = unauthorized();
      await ListMeetings(onList)
          .execute(period: MeetingPeriod.upcoming, request: _firstPage);

      for (final fakes in [onDocument, onList]) {
        expect(fakes.meetingCache.isEmpty(), isTrue);
        expect(fakes.documentCache.isEmpty(), isTrue);
      }
    });

    final refusals = <(String, RepositoryError, void Function(Fakes))>[
      ('forbidden', forbidden(), (fakes) => fakes.meetings.forbid(_meeting.id)),
      (
        'gone',
        notFound(),
        (fakes) => fakes.meetings.removeMeeting(_meeting.id),
      ),
    ];
    for (final (name, refusal, refuse) in refusals) {
      test('removes a meeting that is $name '
          'and every document it lists, and nothing else', () async {
        final fakes = _world();
        final (:other, :otherDocument) = await fillCaches(fakes);
        refuse(fakes);

        final result = await GetMeeting(fakes).execute(meetingId: _meeting.id);

        expect(result, equals(err(refusal)));
        expect(
          await fakes.meetingCache.readMeeting(_alice.id, _meeting.id),
          equals(ok<void>(null)),
        );
        expect(
          await fakes.documentCache.read(_alice.id, aDocument().id),
          equals(ok<void>(null)),
        );
        expect(
          isOk(await fakes.meetingCache.readMeeting(_alice.id, other.id)),
          isTrue,
        );
        final kept = await fakes.documentCache.read(
          _alice.id,
          otherDocument.id,
        );
        expect(_isCached(kept), isTrue);
      });
    }

    test('removes a document that is forbidden, '
        'and only that document', () async {
      final fakes = _world();
      final (:otherDocument, other: _) = await fillCaches(fakes);
      fakes.documents.addDocument(aDocument(), _viewable.location);
      fakes.documents.forbid(aDocument().id);

      final result = await OpenDocument(fakes)
          .execute(documentId: aDocument().id);

      expect(result, equals(err(forbidden())));
      expect(
        await fakes.documentCache.read(_alice.id, aDocument().id),
        equals(ok<void>(null)),
      );
      final kept = await fakes.documentCache.read(_alice.id, otherDocument.id);
      expect(_isCached(kept), isTrue);
      expect(
        isOk(await fakes.meetingCache.readMeeting(_alice.id, _meeting.id)),
        isTrue,
      );
    });

    test('empties everything when a copy cannot be removed, '
        'so that it cannot be served afterwards', () async {
      final fakes = _world();
      await fillCaches(fakes);
      fakes.meetings.addMeeting(_meeting);
      fakes.meetings.forbid(_meeting.id);
      fakes.meetingCache.removeFailure = storageWriteFailed();

      await GetMeeting(fakes).execute(meetingId: _meeting.id);

      expect(fakes.meetingCache.isEmpty(), isTrue);
      expect(fakes.documentCache.isEmpty(), isTrue);
    });

    test('captures the failure when even the purge fails', () async {
      final fakes = _world();
      await fillCaches(fakes);
      fakes.meetings.forbid(_meeting.id);
      fakes.meetingCache.removeFailure = storageWriteFailed();
      fakes.meetingCache.purgeFailure = storageWriteFailed();

      final result = await GetMeeting(fakes).execute(meetingId: _meeting.id);

      expect(result, equals(err(forbidden())));
      expect(
        fakes.monitoring.capturedEvents(),
        contains(MonitoringEvent.cachePurgeFailed),
      );
    });
  });

  group('F4: the screen stays protected '
      'while a confidential document is displayed', () {
    final confidential = aConfidentialDocument();

    test('counts the views of a document: '
        'closing one of two leaves the protection on', () async {
      final fakes = _world();
      fakes.documents.addDocument(confidential, _viewable.location);
      final open = OpenDocument(fakes);
      await open.execute(documentId: confidential.id);
      await open.execute(documentId: confidential.id);

      await CloseDocument(fakes).execute(documentId: confidential.id);
      expect(fakes.screenProtection.enabled, isTrue);

      await CloseDocument(fakes).execute(documentId: confidential.id);
      expect(fakes.screenProtection.enabled, isFalse);
    });
  });

  group('F5: the user is checked again after the remote call', () {
    Future<void> Function() slow(Fakes fakes) => () async {
      await SignOut(fakes).execute();
      await _signInAsBruno(fakes);
    };

    test('writes nothing under the previous owner '
        'when a request spans a sign-out and a sign-in', () async {
      final fakes = _world();
      fakes.meetings.addMeeting(_meeting);
      fakes.meetings.onRequest = slow(fakes);

      final result = await GetMeeting(fakes).execute(meetingId: _meeting.id);

      expect(result, equals(err(sessionChanged())));
      expect(fakes.meetingCache.isEmpty(), isTrue);
    });

    test('does the same for a page of the list', () async {
      final fakes = _world();
      fakes.meetings.setMeetings(MeetingPeriod.upcoming, [aMeetingSummary()]);
      fakes.meetings.onRequest = slow(fakes);

      final result = await ListMeetings(fakes)
          .execute(period: MeetingPeriod.upcoming, request: _firstPage);

      expect(result, equals(err(sessionChanged())));
      expect(fakes.meetingCache.isEmpty(), isTrue);
    });

    test(
      'does not answer from the cache of the previous owner either',
      () async {
        final fakes = _world();
        await fakes.meetingCache.saveMeeting(_alice.id, _meeting, now);
        fakes.network.goOffline();
        fakes.meetings.onRequest = slow(fakes);

        final result = await GetMeeting(fakes).execute(meetingId: _meeting.id);

        expect(result, equals(err(sessionChanged())));
      },
    );

    test('returns no content under the watermark of another user, '
        'and protects nothing for it', () async {
      final fakes = _world();
      fakes.documents.addDocument(aConfidentialDocument(), _viewable.location);
      fakes.documents.onRequest = slow(fakes);

      final result = await OpenDocument(fakes)
          .execute(documentId: aDocument().id);

      expect(result, equals(err(sessionChanged())));
      expect(fakes.screenProtection.enableCalls, equals(0));
      expect(fakes.documentCache.isEmpty(), isTrue);
    });

    test('builds the watermark from the session it checked '
        'after the call', () async {
      final fakes = _world();
      fakes.documents.addDocument(aConfidentialDocument(), _viewable.location);
      // The metadata and the content are two requests: the clock moves during
      // each one.
      fakes.documents.onRequest = () {
        fakes.clock.advance(1000);
      };

      final opened = await OpenDocument(fakes)
          .execute(documentId: aDocument().id);

      final watermark = switch (opened) {
        Ok(:final value) => value.watermark,
        Err() => null,
      };
      expect(
        watermark,
        equals(
          Watermark(
            fullName: _alice.fullName,
            email: _alice.email,
            viewedAt: at(2000),
          ),
        ),
      );
    });
  });

  group('F6: the previous user does not leave their content on the device', () {
    Future<void> aliceLeavesContent(Fakes fakes) async {
      await fakes.meetingCache.saveMeeting(_alice.id, _meeting, now);
      await fakes.documentCache.save(_alice.id, _viewable, now);
    }

    test('empties both caches '
        'when somebody signs in over another user session', () async {
      final fakes = _world();
      await aliceLeavesContent(fakes);

      final signedIn = await _signInAsBruno(fakes);

      expect(isOk(signedIn), isTrue);
      expect(fakes.meetingCache.isEmpty(), isTrue);
      expect(fakes.documentCache.isEmpty(), isTrue);
    });

    test('keeps the caches when the sign-in is refused', () async {
      final fakes = _world();
      await aliceLeavesContent(fakes);

      await SignIn(fakes).execute(email: _bruno.email, password: 'wrong');

      expect(fakes.meetingCache.isEmpty(), isFalse);
    });

    test('retries a purge that failed at sign-out', () async {
      final fakes = _world();
      await aliceLeavesContent(fakes);
      fakes.meetingCache.purgeFailure = storageWriteFailed();
      fakes.documentCache.purgeFailure = storageWriteFailed();
      await SignOut(fakes).execute();
      expect(fakes.meetingCache.isEmpty(), isFalse);
      fakes.meetingCache.purgeFailure = null;
      fakes.documentCache.purgeFailure = null;

      await _signInAsBruno(fakes);

      expect(fakes.meetingCache.isEmpty(), isTrue);
      expect(fakes.documentCache.isEmpty(), isTrue);
    });

    test('still signs the user in, and captures the failure, '
        'when the purge fails', () async {
      final fakes = _world();
      await aliceLeavesContent(fakes);
      fakes.meetingCache.purgeFailure = storageWriteFailed();

      final signedIn = await _signInAsBruno(fakes);

      expect(isOk(signedIn), isTrue);
      expect(
        fakes.monitoring.capturedEvents(),
        contains(MonitoringEvent.cachePurgeFailed),
      );
    });

    test('empties both caches '
        'when a session expires while the app is running', () async {
      final fakes = _world();
      fakes.meetings.addMeeting(_meeting);
      await aliceLeavesContent(fakes);
      fakes.clock.advance(millisPerHour);

      final result = await GetMeeting(fakes).execute(meetingId: _meeting.id);

      expect(result, equals(err(sessionExpired())));
      expect(fakes.meetingCache.isEmpty(), isTrue);
      expect(fakes.documentCache.isEmpty(), isTrue);
      expect(fakes.meetings.getCalls, isEmpty);
    });

    test('still answers sessionExpired, and captures the failure, '
        'when that purge fails', () async {
      final fakes = _world();
      await aliceLeavesContent(fakes);
      fakes.documentCache.purgeFailure = storageWriteFailed();
      fakes.clock.advance(millisPerHour);

      final result = await ListPendingVotes(fakes).execute();

      expect(result, equals(err(sessionExpired())));
      expect(
        fakes.monitoring.capturedEvents(),
        contains(MonitoringEvent.cachePurgeFailed),
      );
    });
  });

  group('F7: smaller leaks', () {
    test('logs a screen capture '
        'with the user who is signed in when it happens', () async {
      final fakes = _world();
      await ObserveScreenCapture(fakes)
          .execute(documentId: aDocumentId(), onCapture: (_) {});
      await SignOut(fakes).execute();
      await _signInAsBruno(fakes);

      fakes.screenProtection.emit(
        const ScreenCaptureEvent(kind: ScreenCaptureKind.screenshotTaken),
      );
      await _settle();

      expect(
        fakes.monitoring.logs.firstOrNull?.attributes?[LogAttribute.userId],
        equals(_bruno.id),
      );
    });

    test('drops the attribution of a capture '
        'when nobody is signed in', () async {
      final fakes = _world();
      var captures = 0;
      await ObserveScreenCapture(fakes).execute(
        documentId: aDocumentId(),
        onCapture: (_) {
          captures++;
        },
      );
      await SignOut(fakes).execute();

      fakes.screenProtection.emit(
        const ScreenCaptureEvent(kind: ScreenCaptureKind.recordingStarted),
      );
      await _settle();

      expect(captures, equals(1));
      expect(fakes.monitoring.logs, hasLength(1));
      final attributes = fakes.monitoring.logs.first.attributes;
      expect(attributes, isNotNull);
      expect(attributes!.containsKey(LogAttribute.userId), isFalse);
    });

    test('refuses to cast a vote '
        'when another user signed in during the biometric prompt', () async {
      final fakes = _world();
      fakes.meetings.addMeeting(_meeting);
      fakes.biometricGate.onPrompt = () async {
        await SignOut(fakes).execute();
        await _signInAsBruno(fakes);
      };

      final result = await CastVote(fakes).execute(
        meetingId: _meeting.id,
        resolutionId: aResolutionId(),
        choice: VoteChoice.forChoice,
      );

      expect(result, equals(err(sessionChanged())));
      expect(fakes.votes.received, isEmpty);
      expect(fakes.outbox.snapshot(), isEmpty);
    });

    test('refuses to cast a vote '
        'when the app was locked during the biometric prompt', () async {
      final fakes = _world();
      fakes.meetings.addMeeting(_meeting);
      fakes.biometricGate.onPrompt = fakes.appLock.lock;

      final result = await CastVote(fakes).execute(
        meetingId: _meeting.id,
        resolutionId: aResolutionId(),
        choice: VoteChoice.forChoice,
      );

      expect(result, equals(err(appLocked())));
      expect(fakes.votes.received, isEmpty);
    });

    test('reports the resolutions and the reasons of a synchronisation, '
        'never the choices', () async {
      final fakes = _world();
      final second = aVote(
        resolutionId: aResolutionId('resolution-2'),
        choice: VoteChoice.against,
      );
      fakes.outbox.seed([aPendingVote(), aPendingVote(second)]);
      fakes.votes.answerNext(ok<void>(null));
      fakes.votes.answerNext(err(const ResolutionClosedError()));

      final report = await SyncPendingVotes(fakes).execute();

      expect(
        unwrap(report),
        isA<SyncCompleted>()
            .having((r) => r.synced, 'synced', equals([aResolutionId()]))
            .having(
              (r) => r.rejected,
              'rejected',
              orderedEquals([
                isA<RejectedSync>()
                    .having(
                      (r) => r.resolutionId,
                      'resolutionId',
                      equals(aResolutionId('resolution-2')),
                    )
                    .having(
                      (r) => r.reason,
                      'reason',
                      equals(const ResolutionClosedError()),
                    ),
              ]),
            ),
      );
      expect('$report', isNot(contains('choice')));
      expect('$report', isNot(contains(VoteChoice.against.value)));
      expect(
        fakes.outbox.snapshot().first,
        isA<OutboxVote>().having(
          (entry) => entry.status,
          'status',
          equals(OutboxStatus.rejected),
        ),
      );
    });
  });
}
