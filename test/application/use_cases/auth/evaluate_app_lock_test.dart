import 'package:boardroom/application/ports/auth_session.dart';
import 'package:boardroom/application/ports/clock.dart';
import 'package:boardroom/application/shared/app_lock.dart';
import 'package:boardroom/application/use_cases/auth/evaluate_app_lock.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import '../../support/create_fakes.dart';

final DurationMillis _gracePeriod = aDuration(30000);

/// The fakes, with a grace period: the Dart counterpart of
/// `{ ...fakes, gracePeriod: GRACE_PERIOD }`.
final class _Deps implements EvaluateAppLockDeps {
  const new(this._fakes);

  final Fakes _fakes;

  @override
  AuthSession get auth => _fakes.auth;

  @override
  Clock get clock => _fakes.clock;

  @override
  DurationMillis get gracePeriod => _gracePeriod;

  @override
  AppLock get appLock => _fakes.appLock;
}

({Fakes fakes, EvaluateAppLock useCase}) _setup() {
  final fakes = createFakes();
  return (fakes: fakes, useCase: EvaluateAppLock(_Deps(fakes)));
}

void main() {
  group('EvaluateAppLock', () {
    test('does not require the unlock when the app returns within the grace '
        'period', () async {
      final (:fakes, :useCase) = _setup();
      fakes.clock.advance(29999);

      expect(await useCase.execute(backgroundedAt: now), equals(ok(false)));
    });

    test('requires the unlock once the grace period has elapsed', () async {
      final (:fakes, :useCase) = _setup();
      fakes.clock.advance(30000);

      expect(await useCase.execute(backgroundedAt: now), equals(ok(true)));
    });

    test('reads the time from the clock at the moment of the call', () async {
      final (:fakes, :useCase) = _setup();

      expect(await useCase.execute(backgroundedAt: now), equals(ok(false)));
      fakes.clock.advance(60000);
      expect(await useCase.execute(backgroundedAt: now), equals(ok(true)));
    });

    test('has nothing to lock when nobody is signed in', () async {
      final (:fakes, :useCase) = _setup();
      fakes.auth.session = null;
      fakes.clock.advance(3600000);

      expect(await useCase.execute(backgroundedAt: now), equals(ok(false)));
    });

    test('has nothing to lock when the session has expired', () async {
      final (:fakes, :useCase) = _setup();
      fakes.auth.session = aSession(expiresAt: at(10000));
      fakes.clock.advance(3600000);

      expect(await useCase.execute(backgroundedAt: now), equals(ok(false)));
    });

    test('requires the unlock when the clock has been set back', () async {
      final (:fakes, :useCase) = _setup();
      fakes.clock.set(at(-1000));

      expect(await useCase.execute(backgroundedAt: now), equals(ok(true)));
    });

    test('returns the storage error when the session cannot be read', () async {
      final (:fakes, :useCase) = _setup();
      fakes.auth.readFailure = storageReadFailed();

      expect(
        await useCase.execute(backgroundedAt: now),
        equals(err(storageReadFailed())),
      );
    });

    group('the lock it enforces', () {
      test('closes the AppLock when the unlock is required, so that nothing '
          'is served until it succeeds', () async {
        final (:fakes, :useCase) = _setup();
        fakes.clock.advance(30000);

        await useCase.execute(backgroundedAt: now);

        expect(fakes.appLock.isLocked(), isTrue);
      });

      test('leaves the AppLock open when the app returns within the grace '
          'period', () async {
        final (:fakes, :useCase) = _setup();
        fakes.clock.advance(29999);

        await useCase.execute(backgroundedAt: now);

        expect(fakes.appLock.isLocked(), isFalse);
      });

      test('closes the AppLock when the clock has been set back: the time '
          'away cannot be known', () async {
        final (:fakes, :useCase) = _setup();
        fakes.clock.set(at(-1000));

        await useCase.execute(backgroundedAt: now);

        expect(fakes.appLock.isLocked(), isTrue);
      });

      test('closes the AppLock when the session cannot be read: it fails '
          'closed', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.readFailure = storageReadFailed();

        await useCase.execute(backgroundedAt: now);

        expect(fakes.appLock.isLocked(), isTrue);
      });

      test(
        'does not touch the AppLock when there is nothing to protect',
        () async {
          final (:fakes, :useCase) = _setup();
          fakes.auth.session = null;
          fakes.clock.advance(3600000);

          await useCase.execute(backgroundedAt: now);

          expect(fakes.appLock.isLocked(), isFalse);
        },
      );
    });
  });
}
