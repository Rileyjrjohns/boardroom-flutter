import 'dart:async';

import 'package:boardroom/application/ports/biometric_gate.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';

/// A device whose biometrics work, until the test says otherwise.
class FakeBiometricGate implements BiometricGate {
  /// What `checkAvailability` answers.
  Result<void, BiometricAvailabilityError> availability = ok<void>(null);

  /// What `authenticate` answers.
  Result<void, BiometricError> authentication = ok<void>(null);

  /// Called when a prompt is shown, before the user answers: a test uses it to
  /// change the world while the user is looking at the prompt (another user
  /// signs in, say).
  FutureOr<void> Function()? onPrompt;

  /// The reason of every prompt shown, in order.
  final List<BiometricReason> prompts = [];

  /// How many times `checkAvailability` was called.
  int availabilityChecks = 0;

  @override
  Future<Result<void, BiometricAvailabilityError>> checkAvailability() async {
    availabilityChecks += 1;
    return availability;
  }

  @override
  Future<Result<void, BiometricError>> authenticate(
    BiometricReason reason,
  ) async {
    prompts.add(reason);
    await onPrompt?.call();
    return authentication;
  }
}
