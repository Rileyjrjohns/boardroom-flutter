import 'package:boardroom/application/ports/screen_protection.dart';
import 'package:boardroom/application/ports/types/unsubscribe.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';

/// The screen protection of the mock configuration. It blocks nothing: it
/// records whether it was turned on, so that the demo and the tests can see
/// what the application asked for, and it can be made to fail or to report a
/// capture. The native adapter is the one of the screen protection plugin.
final class InMemoryScreenProtection implements ScreenProtection {
  bool _enabled = false;
  ScreenProtectionError? _enableFailure;
  ScreenProtectionError? _disableFailure;
  final Set<void Function(ScreenCaptureEvent event)> _listeners = {};

  /// Whether the protection is currently on.
  bool isEnabled() => _enabled;

  /// Makes `enable` fail with this error while set (the protection stays off).
  // ignore: use_setters_to_change_properties
  void failEnableWith(ScreenProtectionError? failure) {
    _enableFailure = failure;
  }

  /// Makes `disable` fail with this error while set (the protection stays as
  /// it was).
  // ignore: use_setters_to_change_properties
  void failDisableWith(ScreenProtectionError? failure) {
    _disableFailure = failure;
  }

  /// Simulates the system reporting a capture to everybody who subscribed.
  void emit(ScreenCaptureEvent event) {
    for (final listener in List.of(_listeners)) {
      listener(event);
    }
  }

  @override
  Future<Result<void, ScreenProtectionError>> enable() async {
    final failure = _enableFailure;
    if (failure != null) {
      return err(failure);
    }
    _enabled = true;
    return ok<void>(null);
  }

  @override
  Future<Result<void, ScreenProtectionError>> disable() async {
    final failure = _disableFailure;
    if (failure != null) {
      return err(failure);
    }
    _enabled = false;
    return ok<void>(null);
  }

  @override
  Unsubscribe subscribe(void Function(ScreenCaptureEvent event) listener) {
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }
}
