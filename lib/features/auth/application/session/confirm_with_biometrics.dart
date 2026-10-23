import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';

/// Asks the user for a biometric proof. The capability is checked first, so
/// that a device without biometrics, or without enrolment, is reported without
/// ever showing a prompt.
Future<Result<void, BiometricError>> confirmWithBiometrics(
  BiometricGate gate,
  BiometricReason reason,
) => andThenAsync<void, void, BiometricError>(
  gate.checkAvailability(),
  (_) => gate.authenticate(reason),
);
