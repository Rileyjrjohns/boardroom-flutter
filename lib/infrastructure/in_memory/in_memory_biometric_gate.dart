import 'package:boardroom/application/ports/biometric_gate.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';

/// The biometrics of the mock configuration: always available, and the user is
/// always recognised, so the demo runs on a simulator without enrolment. A test
/// can make the device lack biometrics, or the user fail, to exercise the paths
/// that fail closed.
final class InMemoryBiometricGate implements BiometricGate {
  Result<void, BiometricAvailabilityError> _availability = ok<void>(null);
  Result<void, BiometricError> _authentication = ok<void>(null);
  final List<BiometricReason> _shown = [];

  /// What `checkAvailability` answers from now on.
  // ignore: use_setters_to_change_properties
  void setAvailability(Result<void, BiometricAvailabilityError> availability) {
    _availability = availability;
  }

  /// What `authenticate` answers from now on.
  // ignore: use_setters_to_change_properties
  void setAuthentication(Result<void, BiometricError> authentication) {
    _authentication = authentication;
  }

  /// The reason of every prompt shown so far, in order.
  List<BiometricReason> prompts() => List.unmodifiable(_shown);

  @override
  Future<Result<void, BiometricAvailabilityError>> checkAvailability() async =>
      _availability;

  @override
  Future<Result<void, BiometricError>> authenticate(
    BiometricReason reason,
  ) async {
    _shown.add(reason);
    return _authentication;
  }
}
