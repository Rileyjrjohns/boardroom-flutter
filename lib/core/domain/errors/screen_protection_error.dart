part of 'app_error.dart';

/// The codes of the screen protection errors.
enum ScreenProtectionErrorCode implements StableValue {
  /// The platform cannot block screenshots and screen recording.
  unsupported('screenProtectionUnsupported'),

  /// The platform could do it, but turning the protection on or off failed.
  failed('screenProtectionFailed');

  new(this.value);

  @override
  final String value;
}

/// What the screen protection can fail with.
sealed class ScreenProtectionError extends AppError {
  /// Creates a screen protection error.
  const new();
}

/// The platform cannot block screenshots and screen recording.
final class ScreenProtectionUnsupportedError extends ScreenProtectionError {
  /// Creates the error.
  const new();

  @override
  String get code => ScreenProtectionErrorCode.unsupported.value;
}

/// The platform could do it, but turning the protection on or off failed.
final class ScreenProtectionFailedError extends ScreenProtectionError {
  /// Creates the error.
  const new();

  @override
  String get code => ScreenProtectionErrorCode.failed.value;
}

/// Builds a [ScreenProtectionUnsupportedError].
ScreenProtectionUnsupportedError screenProtectionUnsupported() =>
    const ScreenProtectionUnsupportedError();

/// Builds a [ScreenProtectionFailedError].
ScreenProtectionFailedError screenProtectionFailed() =>
    const ScreenProtectionFailedError();
