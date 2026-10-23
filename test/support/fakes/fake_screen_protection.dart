import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';

/// A platform that supports screen protection, until the test says otherwise.
class FakeScreenProtection implements ScreenProtection {
  /// Whether the protection is currently on.
  bool enabled = false;

  /// Makes `enable` fail while set (the protection stays off).
  ScreenProtectionError? enableFailure;

  /// Makes `disable` fail while set (the protection stays as it was).
  ScreenProtectionError? disableFailure;

  /// How many times `enable` was called.
  int enableCalls = 0;

  /// How many times `disable` was called.
  int disableCalls = 0;

  final Set<void Function(ScreenCaptureEvent event)> _listeners = {};

  @override
  Future<Result<void, ScreenProtectionError>> enable() async {
    enableCalls += 1;
    final failure = enableFailure;
    if (failure != null) {
      return err(failure);
    }
    enabled = true;
    return ok<void>(null);
  }

  @override
  Future<Result<void, ScreenProtectionError>> disable() async {
    disableCalls += 1;
    final failure = disableFailure;
    if (failure != null) {
      return err(failure);
    }
    enabled = false;
    return ok<void>(null);
  }

  @override
  Unsubscribe subscribe(void Function(ScreenCaptureEvent event) listener) {
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }

  /// Simulates the system reporting a capture.
  void emit(ScreenCaptureEvent event) {
    for (final listener in List.of(_listeners)) {
      listener(event);
    }
  }

  /// How many listeners are subscribed.
  int get listenerCount => _listeners.length;
}
