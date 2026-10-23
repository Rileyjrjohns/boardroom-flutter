import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/use_cases/restore_session.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/builders/names.dart';
import '../../../../support/fakes/create_fakes.dart';
import '../../../../support/fakes/fake_monitoring.dart';

Future<void> _fillCaches(Fakes fakes) async {
  await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
  await fakes.documentCache.save(
    aUserId(),
    ViewableDocument(document: aDocument(), location: aDocumentLocation()),
    now,
  );
}

void main() {
  group('RestoreSession', () {
    group('a stored session that is still valid', () {
      test('is returned together with the requirement to unlock the app: a '
          'cold start always asks for the biometrics', () async {
        final fakes = createFakes();

        expect(
          await RestoreSession(fakes).execute(),
          equals(ok((status: SessionRestore.unlockRequired))),
        );
      });

      test('says nothing of who the user is before the unlock: no name, no '
          'email, no id', () async {
        final fakes = createFakes();

        final restored = await RestoreSession(fakes).execute();

        final text = '$restored';
        expect(text, isNot(contains(aUser().fullName)));
        expect(text, isNot(contains(aUser().email)));
        expect(text, isNot(contains(aUser().id)));
      });

      test('locks the app, even one that was unlocked: no use case serves '
          'anything until the biometrics succeed', () async {
        final fakes = createFakes();
        expect(fakes.appLock.isLocked(), isFalse);

        await RestoreSession(fakes).execute();

        expect(fakes.appLock.isLocked(), isTrue);
      });

      test('is not signed out and leaves the caches alone', () async {
        final fakes = createFakes();
        await _fillCaches(fakes);

        await RestoreSession(fakes).execute();

        expect(fakes.auth.signOutCalls, equals(0));
        expect(fakes.meetingCache.isEmpty(), isFalse);
        expect(fakes.documentCache.isEmpty(), isFalse);
        expect(fakes.monitoring.logs, equals(<LogRecord>[]));
      });

      test('asks to unlock even when the session was stored a moment ago: '
          'nothing says how long the app was away', () async {
        final fakes = createFakes();
        fakes.auth.session = aSession(expiresAt: at(1));

        final result = await RestoreSession(fakes).execute();

        expect(
          result,
          isA<Ok<RestoredSession, StorageReadFailedError>>().having(
            (ok) => ok.value.status,
            'status',
            SessionRestore.unlockRequired,
          ),
        );
      });
    });

    test('reports no session when nobody is signed in', () async {
      final fakes = createFakes();
      fakes.auth.session = null;

      expect(
        await RestoreSession(fakes).execute(),
        equals(ok((status: SessionRestore.none))),
      );
      expect(fakes.auth.signOutCalls, equals(0));
    });

    test(
      'locks the app whatever it finds: a cold start proves nothing',
      () async {
        final none = createFakes();
        none.auth.session = null;
        final expired = createFakes();
        expired.auth.session = aSession(expiresAt: at(-1));
        final unreadable = createFakes();
        unreadable.auth.readFailure = storageReadFailed();

        for (final fakes in [none, expired, unreadable]) {
          await RestoreSession(fakes).execute();
          expect(fakes.appLock.isLocked(), isTrue);
        }
      },
    );

    group('an expired session', () {
      for (final offset in [-1, 0]) {
        test('is signed out (expiry ${formatPretty(offset)} ms from now), and '
            'reported as no session', () async {
          final fakes = createFakes();
          fakes.auth.session = aSession(expiresAt: at(offset));

          expect(
            await RestoreSession(fakes).execute(),
            equals(ok((status: SessionRestore.none))),
          );
          expect(fakes.auth.signOutCalls, equals(1));
          expect(fakes.auth.session, isNull);
          expect(
            fakes.monitoring.logs,
            equals([
              const LogRecord(
                level: LogLevel.info,
                event: MonitoringEvent.sessionExpired,
                attributes: null,
              ),
            ]),
          );
        });
      }

      test('has its caches emptied, so that what the user saw does not stay '
          'on the device', () async {
        final fakes = createFakes();
        await _fillCaches(fakes);
        fakes.auth.session = aSession(expiresAt: at(-1));

        await RestoreSession(fakes).execute();

        expect(fakes.meetingCache.isEmpty(), isTrue);
        expect(fakes.documentCache.isEmpty(), isTrue);
      });

      test('uses the clock of the port, not the real one', () async {
        final fakes = createFakes();
        fakes.auth.session = aSession(expiresAt: at(1000));
        expect(
          await RestoreSession(fakes).execute(),
          equals(ok((status: SessionRestore.unlockRequired))),
        );
        expect(fakes.auth.session, equals(aSession(expiresAt: at(1000))));

        fakes.clock.advance(1000);

        expect(
          await RestoreSession(fakes).execute(),
          equals(ok((status: SessionRestore.none))),
        );
        expect(fakes.auth.session, isNull);
      });

      test('is still reported as no session, and the failures are captured, '
          'when the caches and the sign-out fail', () async {
        final fakes = createFakes();
        fakes.auth.session = aSession(expiresAt: at(-1));
        fakes.auth.signOutFailure = storageWriteFailed();
        fakes.meetingCache.purgeFailure = storageWriteFailed();

        expect(
          await RestoreSession(fakes).execute(),
          equals(ok((status: SessionRestore.none))),
        );
        expect(
          fakes.monitoring.capturedEvents(),
          equals([
            MonitoringEvent.cachePurgeFailed,
            MonitoringEvent.signOutFailed,
          ]),
        );
      });
    });

    test('returns the storage error when the session cannot be read', () async {
      final fakes = createFakes();
      fakes.auth.readFailure = storageReadFailed();

      expect(
        await RestoreSession(fakes).execute(),
        equals(err(storageReadFailed())),
      );
    });
  });
}
