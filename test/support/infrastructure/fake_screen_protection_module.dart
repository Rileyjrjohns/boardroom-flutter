import 'dart:async';

import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/features/documents/infrastructure/native/screen_protection_module_api.dart';
import 'package:screen_protection/screen_protection.dart';

// Test support, not production code. A stand-in for the native side of the
// screen protection plugin, written in Dart, because the real one is Swift
// and Kotlin and needs a device: it is acceptable here, for the adapter, and
// nowhere else.
//
// It behaves like the native side in the ways the adapter depends on:
// `setProtectionEnabled` changes the state when its work is done and not
// before, and a call that is slower (turning on takes longer than turning
// off) finishes later, so an adapter that did not keep the order of its calls
// would show it; an event is delivered, at once, to the listeners that were
// added; and it can be made to fail, to throw, to hang, and to answer with
// what it likes.

/// Turning the protection on takes this many turns of the event loop; turning
/// it off takes none.
const int _turnsToEnable = 3;

/// A native side a test drives.
final class FakeScreenProtectionModule implements ScreenProtectionModuleApi {
  /// Whether the protection is on, as the module has applied it.
  bool enabled = false;

  /// Every value `setProtectionEnabled` was called with, in order of the calls.
  final List<bool> calls = [];

  /// What `isCaptured` answers.
  bool captured = false;

  /// How many times `isCaptured` was called.
  int captureQueries = 0;

  /// The next calls of `setProtectionEnabled` fail with this while set.
  Object? failure;

  /// `setProtectionEnabled` throws instead of returning a future, like a
  /// function that is missing, while set.
  bool throwsSynchronously = false;

  /// `setProtectionEnabled` never answers while set.
  bool hanging = false;

  /// `isCaptured` fails with this while set.
  Object? captureFailure;

  /// `addListener` throws this while set.
  Object? addFailure;

  /// The function returned by `addListener` throws this while set.
  Object? removeFailure;

  Completer<void>? _heldCapture;
  final List<_Listener> _listeners = [];

  /// How many listeners are added.
  int get listenerCount => _listeners.length;

  /// The next `isCaptured` waits for the function returned to be called before
  /// it answers.
  void Function() holdNextCaptureQuery() {
    final held = Completer<void>();
    _heldCapture = held;
    return held.complete;
  }

  /// The system reports a screenshot.
  void emitScreenshot() => emit(ScreenshotTakenMessage());

  /// The system reports that the capture state changed.
  void emitCapture({required bool captured}) =>
      emit(CaptureChangedMessage(captured: captured));

  /// Delivers [event] to the listeners.
  void emit(CaptureEventMessage event) {
    for (final listener in List.of(_listeners)) {
      listener.onEvent(event);
    }
  }

  /// The stream of events fails with [error].
  void emitError(Object error) {
    for (final listener in List.of(_listeners)) {
      listener.onError(error);
    }
  }

  @override
  Future<void> setProtectionEnabled({required bool enabled}) async {
    calls.add(enabled);
    if (throwsSynchronously) {
      throw StateError('setProtectionEnabled is not a function');
    }
    if (hanging) {
      await Completer<void>().future;
      return;
    }
    for (var turn = 0; enabled && turn < _turnsToEnable; turn++) {
      await Future<void>.value();
    }
    final error = failure;
    if (error != null) {
      throw error; // ignore: only_throw_errors, the test chooses what is thrown.
    }
    this.enabled = enabled;
  }

  @override
  Future<bool> isCaptured() async {
    captureQueries += 1;
    final held = _heldCapture;
    _heldCapture = null;
    if (held != null) {
      await held.future;
    }
    final error = captureFailure;
    if (error != null) {
      throw error; // ignore: only_throw_errors, the test chooses what is thrown.
    }
    return captured;
  }

  @override
  Unsubscribe addListener(
    void Function(CaptureEventMessage event) listener, {
    required void Function(Object error) onError,
  }) {
    final error = addFailure;
    if (error != null) {
      throw error; // ignore: only_throw_errors, the test chooses what is thrown.
    }
    final added = _Listener(listener, onError);
    _listeners.add(added);
    return () {
      final removal = removeFailure;
      if (removal != null) {
        throw removal; // ignore: only_throw_errors, the test chooses what is thrown.
      }
      _listeners.remove(added);
    };
  }
}

final class _Listener {
  const new(this.onEvent, this.onError);

  final void Function(CaptureEventMessage event) onEvent;
  final void Function(Object error) onError;
}
