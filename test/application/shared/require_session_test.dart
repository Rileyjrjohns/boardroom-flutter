import 'package:boardroom/application/ports/document_cache.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/shared/app_lock.dart';
import 'package:boardroom/application/shared/require_session.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:test/test.dart';

import '../../domain/support/builders.dart';
import '../support/create_fakes.dart';

Future<void> _fillCaches(Fakes fakes) async {
  await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
  await fakes.documentCache.save(
    aUserId(),
    ViewableDocument(document: aDocument(), location: aDocumentLocation()),
    now,
  );
}

void main() {
  group('requireSession', () {
    test('returns the session of the signed-in user', () async {
      expect(await requireSession(createFakes()), equals(ok(aSession())));
    });

    test('fails with notAuthenticated when nobody is signed in', () async {
      final fakes = createFakes();
      fakes.auth.session = null;

      expect(await requireSession(fakes), equals(err(notAuthenticated())));
    });

    test('fails with sessionExpired once the expiry is reached, the instant '
        'itself included', () async {
      final fakes = createFakes();
      fakes.auth.session = aSession(expiresAt: now);

      expect(await requireSession(fakes), equals(err(sessionExpired())));
    });

    test('accepts a session until its last millisecond', () async {
      final fakes = createFakes();
      fakes.auth.session = aSession(expiresAt: at(1));

      expect(
        await requireSession(fakes),
        equals(ok(aSession(expiresAt: at(1)))),
      );
    });

    test('returns the storage error when the session cannot be read', () async {
      final fakes = createFakes();
      fakes.auth.readFailure = storageReadFailed();

      expect(await requireSession(fakes), equals(err(storageReadFailed())));
    });

    group('when the app is locked', () {
      test('fails with appLocked, though the session is valid', () async {
        final fakes = createFakes().copyWith(appLock: AppLock());

        expect(await requireSession(fakes), equals(err(appLocked())));
      });

      test('serves the user again once the app is unlocked', () async {
        final fakes = createFakes().copyWith(appLock: AppLock());
        fakes.appLock.unlock();

        expect(await requireSession(fakes), equals(ok(aSession())));
      });

      test('says first that nobody is signed in, or that the session expired, '
          'which is more to the point', () async {
        final fakes = createFakes().copyWith(appLock: AppLock());
        fakes.auth.session = null;
        expect(await requireSession(fakes), equals(err(notAuthenticated())));

        fakes.auth.session = aSession(expiresAt: now);
        expect(await requireSession(fakes), equals(err(sessionExpired())));
      });
    });

    group('when the session has expired', () {
      test('empties both caches, for every owner, and still answers '
          'sessionExpired', () async {
        final fakes = createFakes();
        await _fillCaches(fakes);
        await fakes.meetingCache.saveMeeting(
          aUserId('user-2'),
          aMeeting(),
          now,
        );
        fakes.clock.advance(millisPerHour);

        expect(await requireSession(fakes), equals(err(sessionExpired())));

        expect(fakes.meetingCache.isEmpty(), isTrue);
        expect(fakes.documentCache.isEmpty(), isTrue);
      });

      test(
        'captures a purge that fails, and still answers sessionExpired',
        () async {
          final fakes = createFakes();
          await _fillCaches(fakes);
          fakes.meetingCache.purgeFailure = storageWriteFailed();
          fakes.clock.advance(millisPerHour);

          expect(await requireSession(fakes), equals(err(sessionExpired())));

          expect(
            fakes.monitoring.capturedEvents(),
            equals([MonitoringEvent.cachePurgeFailed]),
          );
        },
      );

      test('leaves the caches alone while the session is valid, signed out, or '
          'locked', () async {
        final fakes = createFakes();
        await _fillCaches(fakes);

        await requireSession(fakes);
        fakes.auth.session = null;
        await requireSession(fakes);
        fakes.auth.session = aSession();
        fakes.appLock.lock();
        await requireSession(fakes);

        expect(fakes.meetingCache.isEmpty(), isFalse);
        expect(fakes.documentCache.isEmpty(), isFalse);
      });
    });
  });

  group('requireSameUser', () {
    final other = aSession(user: aUser(id: aUserId('user-2')));

    test(
      'returns the session when the expected user is the one signed in',
      () async {
        expect(
          await requireSameUser(createFakes(), aUserId()),
          equals(ok(aSession())),
        );
      },
    );

    test('fails with sessionChanged when somebody else is signed in', () async {
      final fakes = createFakes();
      fakes.auth.session = other;

      expect(
        await requireSameUser(fakes, aUserId()),
        equals(err(sessionChanged())),
      );
    });

    final changes = <(String, void Function(Fakes), AppError)>[
      (
        'nobody is signed in',
        (fakes) {
          fakes.auth.session = null;
        },
        notAuthenticated(),
      ),
      (
        'the session expired',
        (fakes) {
          fakes.clock.advance(millisPerHour);
        },
        sessionExpired(),
      ),
      (
        'the app is locked',
        (fakes) {
          fakes.appLock.lock();
        },
        appLocked(),
      ),
    ];
    for (final (name, change, expected) in changes) {
      test('fails like the guard when $name', () async {
        final fakes = createFakes();
        change(fakes);

        expect(await requireSameUser(fakes, aUserId()), equals(err(expected)));
      });
    }
  });
}
