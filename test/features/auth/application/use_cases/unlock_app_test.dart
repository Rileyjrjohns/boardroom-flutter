import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/application/use_cases/unlock_app.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:test/test.dart';

import '../../../../support/fakes/create_fakes.dart';

UnlockApp _unlockApp(Fakes fakes) => UnlockApp(fakes);

void main() {
  group('UnlockApp', () {
    test(
      'unlocks the app with a biometric proof for the unlock reason',
      () async {
        final fakes = createFakes();

        expect(await _unlockApp(fakes).execute(), equals(ok<void>(null)));
        expect(
          fakes.biometricGate.prompts,
          equals([BiometricReason.unlockApp]),
        );
      },
    );

    test('returns the refusal of the user', () async {
      final fakes = createFakes();
      fakes.biometricGate.authentication = err(biometricCancelled());

      expect(
        await _unlockApp(fakes).execute(),
        equals(err(biometricCancelled())),
      );
    });

    test(
      'reports a device without biometrics before showing a prompt',
      () async {
        final fakes = createFakes();
        fakes.biometricGate.availability = err(biometricUnavailable());

        expect(
          await _unlockApp(fakes).execute(),
          equals(err(biometricUnavailable())),
        );
        expect(fakes.biometricGate.prompts, equals(<BiometricReason>[]));
      },
    );

    group('the lock it opens', () {
      test('opens the AppLock when the biometrics succeed', () async {
        final fakes = createFakes();
        fakes.appLock.lock();

        await _unlockApp(fakes).execute();

        expect(fakes.appLock.isLocked(), isFalse);
      });

      for (final (name, refusal) in <(String, Result<void, BiometricError>)>[
        ('the user cancels', err(biometricCancelled())),
        ('the user is not recognised', err(biometricFailed())),
      ]) {
        test('leaves the AppLock closed when $name', () async {
          final fakes = createFakes();
          fakes.appLock.lock();
          fakes.biometricGate.authentication = refusal;

          await _unlockApp(fakes).execute();

          expect(fakes.appLock.isLocked(), isTrue);
        });
      }

      test(
        'leaves the AppLock closed when the device has no biometrics',
        () async {
          final fakes = createFakes();
          fakes.appLock.lock();
          fakes.biometricGate.availability = err(biometricUnavailable());

          await _unlockApp(fakes).execute();

          expect(fakes.appLock.isLocked(), isTrue);
        },
      );
    });
  });
}
