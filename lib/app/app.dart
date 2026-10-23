import 'package:boardroom/app/home_screen.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Root widget of the app.
///
/// For now it only wires localization and shows a placeholder home screen.
/// Routing and the providers of the composition come in later steps.
class BoardroomApp extends StatelessWidget {
  /// Creates the root widget; [locale] forces a language (tests use it),
  /// otherwise the language of the device is used with English as fallback.
  const new({super.key, this.locale});

  /// Language to force, or null to follow the device.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomeScreen(),
    );
  }
}
