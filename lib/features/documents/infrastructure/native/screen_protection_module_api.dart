import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:screen_protection/screen_protection.dart'
    show CaptureEventMessage;

/// What the adapter asks of the native side of the screen protection plugin:
/// the seam it is written against, as `NetworkStateApi` is for the
/// connectivity plugin. `PigeonScreenProtectionModule` is the one over the
/// plugin; the tests give the adapter a stand-in written in Dart.
///
/// Any call may fail, throw or never answer: the adapter bounds them and turns
/// a failure into a result.
abstract interface class ScreenProtectionModuleApi {
  /// Turns the protection on or off. Idempotent. Completes once the change has
  /// been made.
  Future<void> setProtectionEnabled({required bool enabled});

  /// Whether the screen is being recorded, mirrored or AirPlayed right now.
  Future<bool> isCaptured();

  /// Listens to the capture events of the native side. The system listeners
  /// behind them exist while one is added. [onError] is told when the stream of
  /// events fails. The function returned stops this listener; it may throw.
  Unsubscribe addListener(
    void Function(CaptureEventMessage event) listener, {
    required void Function(Object error) onError,
  });
}
