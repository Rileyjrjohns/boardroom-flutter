import 'dart:async';

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/shared/attempt.dart';
import 'package:boardroom/core/infrastructure/shared/serial_queue.dart';
import 'package:boardroom/core/infrastructure/shared/subscribers.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/features/documents/infrastructure/native/screen_protection_module_api.dart';
import 'package:screen_protection/screen_protection.dart'
    show CaptureChangedMessage, CaptureEventMessage, ScreenshotTakenMessage;

/// How long the native side may take to turn the protection on or off, or to
/// say how the screen is.
const int defaultNativeTimeoutMillis = 5000;

const _screenshot = ScreenCaptureEvent(kind: ScreenCaptureKind.screenshotTaken);
const _recordingStarted = ScreenCaptureEvent(
  kind: ScreenCaptureKind.recordingStarted,
);
const _recordingStopped = ScreenCaptureEvent(
  kind: ScreenCaptureKind.recordingStopped,
);

/// The [ScreenProtection] port over the screen protection plugin of the app
/// (`packages/screen_protection`), through [ScreenProtectionModuleApi].
///
/// - **Enable and disable** go to the module one at a time, in the order they
///   were issued, so a `disable` issued first can never land after an `enable`.
///   Each is bounded in time. A module that fails, throws or does not answer is
///   a `screenProtectionFailed` result, and a missing module (the platform has
///   no plugin) is `screenProtectionUnsupported`: nothing escapes, and a
///   failure is also captured by the monitoring, with the kind of failure and
///   nothing else. Disabling something that cannot be enabled succeeds: it is
///   off.
/// - **Capture events** are the module's, mapped to the port's: a screenshot,
///   and a recording that starts or stops. The listener of the module exists
///   only while someone is subscribed, one for every subscriber together. A
///   change is told once: a report that repeats the known state is dropped.
/// - **A recording that is already running** when someone starts listening is
///   told to them as a `recordingStarted`, from `isCaptured`: the module
///   reports changes, and a document opened while the screen is recorded needs
///   to know. A change that arrives first wins over that answer.
///
/// Every call of `subscribe` is a subscription of its own, and a listener that
/// throws is captured and does not stop the others (`createSubscribers`).
final class NativeScreenProtection implements ScreenProtection {
  /// Creates the adapter over [module], or over nothing when the platform has
  /// no plugin. [monitoring] is told when the native side fails, and when a
  /// listener throws, which it must not. [timeoutMillis] defaults to
  /// [defaultNativeTimeoutMillis].
  new({
    required this.module,
    required this.monitoring,
    this.timeoutMillis = defaultNativeTimeoutMillis,
  }) {
    _subscribers = createSubscribers<ScreenCaptureEvent>(_onListenerError);
  }

  /// The native side, or null when the platform has none.
  final ScreenProtectionModuleApi? module;

  /// Told when the native side fails, and when a listener throws.
  final Monitoring monitoring;

  /// How long a call to the native side may take.
  final int timeoutMillis;

  final SerialQueue _queue = createSerialQueue();
  late final Subscribers<ScreenCaptureEvent> _subscribers;

  Unsubscribe? _nativeListener;
  bool _listening = false;

  /// Whether the screen is captured, as far as is known; only while listening.
  bool? _captured;

  /// Tells a listening that ended from the one that replaced it, for the
  /// answers that come late.
  int _session = 0;

  @override
  Future<Result<void, ScreenProtectionError>> enable() =>
      _queue(() => _setEnabled(enabled: true));

  @override
  Future<Result<void, ScreenProtectionError>> disable() =>
      _queue(() => _setEnabled(enabled: false));

  @override
  Unsubscribe subscribe(void Function(ScreenCaptureEvent event) listener) {
    var active = true;
    final stop = _subscribers.subscribe(listener);
    if (!_listening) {
      _startListening();
    } else if (_captured ?? false) {
      // The recording began before this subscriber came: tell it, once its
      // subscription is made.
      scheduleMicrotask(() {
        if (active) {
          _deliver(listener, _recordingStarted);
        }
      });
    }

    return () {
      active = false;
      stop();
      if (_subscribers.size == 0) {
        _stopListening();
      }
    };
  }

  Future<Result<void, ScreenProtectionError>> _setEnabled({
    required bool enabled,
  }) async {
    final module = this.module;
    if (module == null) {
      if (enabled) {
        return err(screenProtectionUnsupported());
      }
      return ok<void>(null);
    }

    final done = await attempt<void>(
      () => module.setProtectionEnabled(enabled: enabled),
      timeoutMillis,
    );
    switch (done) {
      case Ok():
        return ok<void>(null);
      case Err(:final error):
        monitoring.captureError(
          MonitoringEvent.screenProtectionNativeFailed,
          screenProtectionFailed(),
          {LogAttribute.reason: error.cause},
        );
        return err(screenProtectionFailed());
    }
  }

  void _startListening() {
    _listening = true;
    _captured = null;
    _session += 1;

    final module = this.module;
    if (module == null) {
      return;
    }

    try {
      _nativeListener = module.addListener(
        _onNativeEvent,
        onError: _reportNativeFailure,
      );
    } on Object catch (error) {
      // A listener that cannot be added only means the events never come.
      _reportNativeFailure(error);
    }
    unawaited(_readInitialCapture(module, _session));
  }

  void _stopListening() {
    if (!_listening) {
      return;
    }
    _listening = false;
    _captured = null;
    final listener = _nativeListener;
    _nativeListener = null;
    if (listener == null) {
      return;
    }
    try {
      listener();
    } on Object catch (error) {
      _reportNativeFailure(error);
    }
  }

  void _onNativeEvent(CaptureEventMessage event) {
    if (!_listening) {
      return;
    }
    switch (event) {
      case ScreenshotTakenMessage():
        _subscribers.notify(_screenshot);
      case CaptureChangedMessage(:final captured):
        if (captured == _captured) {
          return;
        }
        _captured = captured;
        _subscribers.notify(captured ? _recordingStarted : _recordingStopped);
    }
  }

  /// Learns whether a recording is already running, unless a change has told so
  /// first.
  Future<void> _readInitialCapture(
    ScreenProtectionModuleApi module,
    int session,
  ) async {
    final asked = await attempt<bool>(module.isCaptured, timeoutMillis);
    if (asked is! Ok<bool, AttemptFailure>) {
      return;
    }
    if (!_listening || session != _session || _captured != null) {
      return;
    }

    final captured = asked.value;
    _captured = captured;
    if (captured) {
      _subscribers.notify(_recordingStarted);
    }
  }

  void _deliver(
    void Function(ScreenCaptureEvent event) listener,
    ScreenCaptureEvent event,
  ) {
    createSubscribers<ScreenCaptureEvent>(_onListenerError)
      ..subscribe(listener)
      ..notify(event);
  }

  void _onListenerError(Object error) {
    monitoring.captureError(
      MonitoringEvent.screenProtectionListenerFailed,
      screenProtectionFailed(),
      {LogAttribute.reason: describeFailure(error)},
    );
  }

  void _reportNativeFailure(Object error) {
    monitoring.captureError(
      MonitoringEvent.screenProtectionNativeFailed,
      screenProtectionFailed(),
      {LogAttribute.reason: describeFailure(error)},
    );
  }
}
