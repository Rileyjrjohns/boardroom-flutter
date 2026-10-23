import 'package:boardroom/app/shell/startup_gate.dart';
import 'package:flutter/widgets.dart';

export 'package:boardroom/app/shell/startup_gate.dart' show StartApp;

/// Root widget of the app: the startup gate, which builds the composition root
/// with [start], then mounts the providers, the session controller and the
/// router. `main` gives the real start; a test gives one that answers with a
/// container over fakes.
class BoardroomApp extends StatelessWidget {
  /// Creates the root widget; [locale] forces a language (tests use it),
  /// otherwise the language of the device is used with English as fallback.
  const new({required this.start, this.locale, super.key});

  /// Builds the composition root.
  final StartApp start;

  /// Language to force, or null to follow the device.
  final Locale? locale;

  @override
  Widget build(BuildContext context) =>
      StartupGate(start: start, locale: locale);
}
