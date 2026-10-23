import 'package:boardroom/app/home_screen.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/infrastructure/in_memory_screen_protection.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Root widget of the app.
///
/// For now it only wires localization and shows a placeholder home screen.
/// Routing and the providers of the composition come in later steps.
///
/// The screen protection is the one adapter handed in: `main` gives the native
/// one, and without one (the tests) the screen protection of the mock
/// configuration blocks nothing.
class BoardroomApp extends StatelessWidget {
  /// Creates the root widget; [locale] forces a language (tests use it),
  /// otherwise the language of the device is used with English as fallback.
  new({super.key, this.locale, ScreenProtection? screenProtection})
    : screenProtection = screenProtection ?? InMemoryScreenProtection();

  /// Language to force, or null to follow the device.
  final Locale? locale;

  /// The adapter of the `ScreenProtection` port the demo screen drives.
  final ScreenProtection screenProtection;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(screenProtection: screenProtection),
    );
  }
}
