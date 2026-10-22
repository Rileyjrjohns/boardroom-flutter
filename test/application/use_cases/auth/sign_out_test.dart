import 'package:boardroom/application/ports/document_cache.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/use_cases/auth/sign_out.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import '../../support/create_fakes.dart';

Future<void> _fillCaches(Fakes fakes) async {
  await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
  await fakes.documentCache.save(
    aUserId(),
    ViewableDocument(document: aDocument(), location: aDocumentLocation()),
    now,
  );
}

void main() {
  group('SignOut', () {
    test('forgets the session', () async {
      final fakes = createFakes();

      expect(await SignOut(fakes).execute(), equals(ok<void>(null)));
      expect(fakes.auth.session, isNull);
    });

    test('empties the meeting cache and the document cache, so that nothing '
        'the user saw stays on the device', () async {
      final fakes = createFakes();
      await _fillCaches(fakes);

      await SignOut(fakes).execute();

      expect(fakes.meetingCache.isEmpty(), isTrue);
      expect(fakes.documentCache.isEmpty(), isTrue);
      expect(
        await fakes.meetingCache.readMeeting(aUserId(), aMeetingId()),
        equals(ok<void>(null)),
      );
    });

    test('does not touch the vote outbox: the votes of the user wait for them '
        'to come back', () async {
      final fakes = createFakes();
      fakes.outbox.seed([aPendingVote()]);

      await SignOut(fakes).execute();

      expect(fakes.outbox.snapshot(), equals([aPendingVote()]));
    });

    test('succeeds when nobody was signed in', () async {
      final fakes = createFakes();
      fakes.auth.session = null;

      expect(await SignOut(fakes).execute(), equals(ok<void>(null)));
    });

    test('still signs out, and captures the failure, when a cache cannot be '
        'emptied', () async {
      final fakes = createFakes();
      await _fillCaches(fakes);
      fakes.meetingCache.purgeFailure = storageWriteFailed();
      fakes.documentCache.purgeFailure = storageWriteFailed();

      expect(await SignOut(fakes).execute(), equals(ok<void>(null)));
      expect(fakes.auth.session, isNull);
      expect(
        fakes.monitoring.capturedEvents(),
        equals([
          MonitoringEvent.cachePurgeFailed,
          MonitoringEvent.cachePurgeFailed,
        ]),
      );
    });

    test('returns the storage error when the session cannot be removed, and '
        'the caches are empty anyway', () async {
      final fakes = createFakes();
      await _fillCaches(fakes);
      fakes.auth.signOutFailure = storageWriteFailed();

      expect(await SignOut(fakes).execute(), equals(err(storageWriteFailed())));
      expect(fakes.auth.session, equals(aSession()));
      expect(fakes.meetingCache.isEmpty(), isTrue);
    });

    test(
      'locks the app: the next user signs in, which opens it again',
      () async {
        final fakes = createFakes();

        await SignOut(fakes).execute();

        expect(fakes.appLock.isLocked(), isTrue);
      },
    );

    test('locks the app even when the caches cannot be emptied and the '
        'sign-out fails', () async {
      final fakes = createFakes();
      fakes.meetingCache.purgeFailure = storageWriteFailed();
      fakes.auth.signOutFailure = storageWriteFailed();

      await SignOut(fakes).execute();

      expect(fakes.appLock.isLocked(), isTrue);
    });
  });
}
