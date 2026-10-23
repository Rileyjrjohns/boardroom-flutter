import 'package:flutter/widgets.dart';
import 'package:screen_protection/screen_protection_view.dart';

/// Puts its child in a container that is left out of screenshots and screen
/// recordings while [secure] is on. With [secure] off it is a plain container.
///
/// **The one file of the presentation that imports the screen protection
/// plugin**, and only its widget entry point (`screen_protection_view.dart`).
/// Everything else reaches the screen protection through the `ScreenProtection`
/// port, and `tool/check_imports.dart` says so: this exemption is listed there
/// by file and by URI, and tested. It is a narrow exception made for a reason
/// the port cannot serve: a port carries data and calls, and what is needed
/// here is a native *view*, an element of the tree that the content is mounted
/// with. A view cannot cross a port, so the file that mounts it is the adapter
/// of that view.
///
/// The other way would be a widget in `infrastructure/` that composition hands
/// to the screens. It was not chosen because nothing hands widgets down before
/// the router of the next step: it would need a provider that does not exist
/// yet, and a screen that gets a builder from it is no simpler to read than a
/// screen that names `SecureContent`. The exemption costs one line of the
/// checker and keeps the widget where the screens find it.
///
/// What it does depends on the platform. On Android the window flag of the
/// screen protection already keeps the whole window out of captures, so the
/// child is rendered as it is. On iOS the content is left out through a private
/// flag of the system, that exists only while a secure container is shown, and
/// that the system may stop accepting: the plugin reports it, and [onFallback]
/// is called with the reason, for a log and not for the user.
class SecureContent extends StatelessWidget {
  /// Creates a container of [child] that is secure while [secure] is on.
  const new({
    required this.secure,
    required this.child,
    super.key,
    this.onFallback,
  });

  /// Whether the content must come out blank in screenshots and screen
  /// recordings.
  final bool secure;

  /// Called when the system cannot leave the content out of captures.
  final void Function(String reason)? onFallback;

  /// The content.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SecureView(secure: secure, onFallback: onFallback, child: child);
}
