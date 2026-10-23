import 'package:boardroom/app/dev/in_memory/in_memory_biometric_gate.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryBiometricGate', () {
    test('is available and recognises the user, so that the demo runs on a '
        'simulator', () async {
      final gate = InMemoryBiometricGate();

      expect(await gate.checkAvailability(), equals(ok<void>(null)));
      expect(
        await gate.authenticate(BiometricReason.unlockApp),
        equals(ok<void>(null)),
      );
    });

    test('remembers the reason of every prompt it showed, in order', () async {
      final gate = InMemoryBiometricGate();

      await gate.authenticate(BiometricReason.unlockApp);
      await gate.authenticate(BiometricReason.confirmVote);

      expect(
        gate.prompts(),
        equals([BiometricReason.unlockApp, BiometricReason.confirmVote]),
      );
    });

    test('hands out a copy of the prompts it remembers', () async {
      final gate = InMemoryBiometricGate();
      await gate.authenticate(BiometricReason.unlockApp);

      // The copy is not modifiable: nobody can empty what the gate remembers.
      expect(() => gate.prompts().clear(), throwsUnsupportedError);
      expect(gate.prompts(), equals([BiometricReason.unlockApp]));
    });

    test(
      'can be made unavailable, or made to refuse the user, for a test',
      () async {
        final gate = InMemoryBiometricGate()
          ..setAvailability(err(biometricNotEnrolled()));
        expect(
          await gate.checkAvailability(),
          equals(err(biometricNotEnrolled())),
        );
        gate.setAvailability(err(biometricUnavailable()));
        expect(
          await gate.checkAvailability(),
          equals(err(biometricUnavailable())),
        );

        gate.setAuthentication(err(biometricCancelled()));
        expect(
          await gate.authenticate(BiometricReason.confirmVote),
          equals(err(biometricCancelled())),
        );
      },
    );
  });
}
