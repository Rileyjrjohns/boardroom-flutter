import 'dart:async';

import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/features/documents/infrastructure/native/screen_protection_module_api.dart';
import 'package:flutter/foundation.dart';
import 'package:screen_protection/screen_protection.dart';

/// The native side of the screen protection, over the typed channel the plugin
/// generates with Pigeon. The host and the events default to the plugin's own
/// and are given by the tests, which have no native side to talk to.
final class PigeonScreenProtectionModule implements ScreenProtectionModuleApi {
  /// Creates the module over `host` and the stream made by `events`.
  new({
    ScreenProtectionHostApi? host,
    Stream<CaptureEventMessage> Function()? events,
  }) : _host = host ?? ScreenProtectionHostApi(),
       _eventsFactory = events ?? streamCaptureEvents;

  final ScreenProtectionHostApi _host;
  final Stream<CaptureEventMessage> Function() _eventsFactory;

  // The plugin makes a channel for each call of its function, so the stream is
  // made once and every listener shares it.
  late final Stream<CaptureEventMessage> _events = _eventsFactory();

  @override
  Future<void> setProtectionEnabled({required bool enabled}) =>
      _host.setProtectionEnabled(enabled);

  @override
  Future<bool> isCaptured() => _host.isCaptured();

  @override
  Unsubscribe addListener(
    void Function(CaptureEventMessage event) listener, {
    required void Function(Object error) onError,
  }) {
    final subscription = _events.listen(listener, onError: onError);
    return () {
      unawaited(
        subscription.cancel().onError<Object>((error, _) => onError(error)),
      );
    };
  }
}

/// The native side of the screen protection, or null when the platform has no
/// plugin for it (the web, the desktop, a test host): the platform cannot
/// protect the screen, and the adapter says so. This is the one place that
/// knows which platforms have the plugin. [platform] defaults to the platform
/// of the app.
ScreenProtectionModuleApi? loadScreenProtectionModule({
  TargetPlatform? platform,
}) {
  if (kIsWeb) {
    return null;
  }
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS => PigeonScreenProtectionModule(),
    _ => null,
  };
}
