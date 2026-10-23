import 'package:boardroom/app/shell/header_actions.dart';
import 'package:flutter/material.dart';

/// The frame of a route: the header with the title of the screen (the navigator
/// of the React Native app owns the titles, the screens do not), and the screen
/// itself as the body. The screens of the features have no `Scaffold` of their
/// own.
class RouteScaffold extends StatelessWidget {
  /// Creates the frame around [child].
  const new({
    required this.title,
    required this.child,
    this.showHeaderActions = false,
    super.key,
  });

  /// The translated title of the route.
  final String title;

  /// The screen.
  final Widget child;

  /// Whether the header carries the header actions (the home route only).
  final bool showHeaderActions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: showHeaderActions ? const [HeaderActions()] : null,
    ),
    body: SafeArea(child: child),
  );
}
