import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_protection/src/messages.g.dart';

/// The identifier the iOS plugin registers its secure view under.
const String secureViewType = 'screen_protection/secure_view';

/// Size of the native view that stands for the secure content: it draws
/// nothing and takes no touch, it only has to exist while the content is shown.
const double _markerSize = 1;

/// Shows [child] and, while [secure] is on, keeps it out of screenshots and
/// screen recordings.
///
/// - On Android the window flag of the protection (`FLAG_SECURE`) already keeps
///   the whole window out of captures, so the child is rendered as it is.
/// - On iOS a native view is mounted next to the child while [secure] is on.
///   Flutter draws all its widgets into one surface, so the native view marks
///   that surface with the private flag UIKit sets for a secure text field: the
///   whole Flutter view is left out of captures while a secure view is
///   mounted, and shown again when the last one is removed. The flag is
///   undocumented: where the system lacks it the content is visible in
///   captures and [onFallback] is called with the reason.
/// - On any other platform the child is rendered as it is.
class SecureView extends StatefulWidget {
  /// Creates a secure view of [child].
  const new({
    required this.child,
    super.key,
    this.secure = true,
    this.onFallback,
    @visibleForTesting this.fallbacks,
  });

  /// The content to keep out of captures.
  final Widget child;

  /// Whether the content must be left out of captures. When it is off the view
  /// is a plain container and no native view exists.
  final bool secure;

  /// Called with a sentence for a log when the system cannot leave the content
  /// out of captures. It is not for the user.
  final void Function(String reason)? onFallback;

  /// The fallbacks of the native side. Tests give their own; the app uses the
  /// stream of the plugin.
  @visibleForTesting
  final Stream<SecureLayerFallbackMessage>? fallbacks;

  @override
  State<SecureView> createState() => _SecureViewState();
}

class _SecureViewState extends State<SecureView> {
  StreamSubscription<SecureLayerFallbackMessage>? _subscription;

  bool get _native =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && widget.secure;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(SecureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secure != widget.secure) {
      _listen();
    }
  }

  // Listens to the fallbacks while a native view exists, so that the listener
  // is in place before the view reports.
  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (!_native) {
      return;
    }
    _subscription = (widget.fallbacks ?? streamSecureLayerFallbacks()).listen((
      message,
    ) {
      widget.onFallback?.call(message.reason);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_native) {
      return widget.child;
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        const Positioned(
          left: 0,
          top: 0,
          width: _markerSize,
          height: _markerSize,
          child: IgnorePointer(
            child: UiKitView(
              viewType: secureViewType,
              creationParamsCodec: StandardMessageCodec(),
            ),
          ),
        ),
      ],
    );
  }
}
