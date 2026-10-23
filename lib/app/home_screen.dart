import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/presentation/screen_protection_demo_screen.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Placeholder home screen: the app name, a "coming soon" line, and the way to
/// the screen that tries the screen protection on a device (until the router
/// has the real screens).
///
/// Every text comes from the ARB files, never from a literal.
class HomeScreen extends StatelessWidget {
  /// Creates the placeholder home screen; [screenProtection] is the port the
  /// demo screen drives.
  const new({required this.screenProtection, super.key});

  /// The port the demo screen of the screen protection drives.
  final ScreenProtection screenProtection;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.homeComingSoon),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ScreenProtectionDemoScreen(
                    screenProtection: screenProtection,
                  ),
                ),
              ),
              child: Text(l10n.homeOpenScreenProtectionDemo),
            ),
          ],
        ),
      ),
    );
  }
}
