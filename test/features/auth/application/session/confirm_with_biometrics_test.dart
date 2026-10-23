import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/application/session/confirm_with_biometrics.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:test/test.dart';

import '../../../../support/builders/names.dart';
import '../../../../support/fakes/fake_biometric_gate.dart';

void main() {
  group('confirmWithBiometrics', () {
    test('shows the prompt for the reason and succeeds when the user is '
        'recognised', () async {
      final gate = FakeBiometricGate();

      expect(
        await confirmWithBiometrics(gate, BiometricReason.confirmVote),
        equals(ok<void>(null)),
      );
      expect(gate.prompts, equals([BiometricReason.confirmVote]));
    });

    for (final error in <BiometricAvailabilityError>[
      biometricUnavailable(),
      biometricNotEnrolled(),
    ]) {
      test(
        'reports ${formatPretty(error)} without showing any prompt',
        () async {
          final gate = FakeBiometricGate()..availability = err(error);

          expect(
            await confirmWithBiometrics(gate, BiometricReason.unlockApp),
            equals(err(error)),
          );
          expect(gate.prompts, isEmpty);
        },
      );
    }

    test('returns the error of the authentication', () async {
      final gate = FakeBiometricGate()
        ..authentication = err(biometricCancelled());

      expect(
        await confirmWithBiometrics(gate, BiometricReason.unlockApp),
        equals(err(biometricCancelled())),
      );
    });
  });
}
