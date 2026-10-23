import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'screen_protection.freezed.dart';

/// What the system reports about the screen being captured.
enum ScreenCaptureKind implements StableValue {
  /// A screenshot was taken.
  screenshotTaken('screenshotTaken'),

  /// A screen recording or mirroring started.
  recordingStarted('recordingStarted'),

  /// A screen recording or mirroring stopped.
  recordingStopped('recordingStopped');

  new(this.value);

  @override
  final String value;
}

/// A capture reported by the system.
@freezed
abstract class ScreenCaptureEvent with _$ScreenCaptureEvent {
  /// Creates an event.
  const factory({required ScreenCaptureKind kind}) = _ScreenCaptureEvent;
}

/// Blocks screenshots and screen recording while a confidential screen is
/// shown, and reports attempts.
///
/// The port is deliberately dumb: it is one global switch with no memory of who
/// asked for it. Which documents need it, and when the last one has gone, is
/// decided by the application (`ScreenProtectionCoordinator`), so that every
/// adapter behaves the same.
///
/// Contract: no method throws, and `enable` and `disable` settle in bounded
/// time. They are idempotent. `enable` has taken effect when it completes: a
/// screen shown after it is protected (a capture started afterwards is blocked,
/// and the app switcher shows no content). Calls are applied in the order they
/// were issued, so a `disable` issued before an `enable` can never land after
/// it; the application also serialises its own calls
/// (`ScreenProtectionCoordinator`). A listener must not throw; the adapter
/// calls it for each event until it is unsubscribed.
abstract interface class ScreenProtection {
  /// Turns the protection on. Fails when the platform cannot provide it.
  Future<Result<void, ScreenProtectionError>> enable();

  /// Turns the protection off. Succeeds when it was already off.
  Future<Result<void, ScreenProtectionError>> disable();

  /// Calls [listener] for each capture event, until the returned function is
  /// called.
  Unsubscribe subscribe(void Function(ScreenCaptureEvent event) listener);
}
