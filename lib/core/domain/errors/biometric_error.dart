part of 'app_error.dart';

/// The codes of the biometric errors.
enum BiometricErrorCode implements StableValue {
  /// The device has no biometric hardware, or the app may not use it.
  unavailable('biometricUnavailable'),

  /// The device has biometric hardware but nothing is registered.
  notEnrolled('biometricNotEnrolled'),

  /// The user dismissed the prompt.
  cancelled('biometricCancelled'),

  /// The prompt was shown and the user did not match.
  failed('biometricFailed'),

  /// Too many failed attempts: the system refuses new ones for a while.
  lockedOut('biometricLockedOut');

  new(this.value);

  @override
  final String value;
}

/// What an authentication can fail with.
sealed class BiometricError extends AppError {
  /// Creates a biometric error.
  const new();
}

/// What a check of the biometric capability can report: the device cannot do it
/// ([BiometricUnavailableError]) or the user has not set it up
/// ([BiometricNotEnrolledError]).
sealed class BiometricAvailabilityError extends BiometricError {
  /// Creates a biometric availability error.
  const new();
}

/// The device has no biometric hardware, or the app may not use it.
final class BiometricUnavailableError extends BiometricAvailabilityError {
  /// Creates the error.
  const new();

  @override
  String get code => BiometricErrorCode.unavailable.value;
}

/// The device has biometric hardware but the user has registered no fingerprint
/// or face.
final class BiometricNotEnrolledError extends BiometricAvailabilityError {
  /// Creates the error.
  const new();

  @override
  String get code => BiometricErrorCode.notEnrolled.value;
}

/// The user dismissed the prompt.
final class BiometricCancelledError extends BiometricError {
  /// Creates the error.
  const new();

  @override
  String get code => BiometricErrorCode.cancelled.value;
}

/// The prompt was shown and the user did not match.
final class BiometricFailedError extends BiometricError {
  /// Creates the error.
  const new();

  @override
  String get code => BiometricErrorCode.failed.value;
}

/// Too many failed attempts: the system refuses new ones for a while.
final class BiometricLockedOutError extends BiometricError {
  /// Creates the error.
  const new();

  @override
  String get code => BiometricErrorCode.lockedOut.value;
}

/// Builds a [BiometricUnavailableError].
BiometricUnavailableError biometricUnavailable() =>
    const BiometricUnavailableError();

/// Builds a [BiometricNotEnrolledError].
BiometricNotEnrolledError biometricNotEnrolled() =>
    const BiometricNotEnrolledError();

/// Builds a [BiometricCancelledError].
BiometricCancelledError biometricCancelled() => const BiometricCancelledError();

/// Builds a [BiometricFailedError].
BiometricFailedError biometricFailed() => const BiometricFailedError();

/// Builds a [BiometricLockedOutError].
BiometricLockedOutError biometricLockedOut() => const BiometricLockedOutError();
