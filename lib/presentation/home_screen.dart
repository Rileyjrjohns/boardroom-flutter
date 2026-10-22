import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Placeholder home screen: the app name and a "coming soon" line.
///
/// Every text comes from the ARB files, never from a literal.
class HomeScreen extends StatelessWidget {
  /// Creates the placeholder home screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(child: Text(l10n.homeComingSoon)),
    );
  }
}
