import 'package:boardroom/app/composition/use_cases.dart';
import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/presentation/demo/demo_controls.dart';
import 'package:boardroom/core/presentation/notices/app_notices.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:meta/meta.dart';

/// The values the screens need that come from the configuration (see
/// `settings.dart`).
@immutable
final class AppSettings {
  /// Creates the settings of the screens.
  const new({required this.meetingsPageSize});

  /// How many meetings a page of the list holds.
  final int meetingsPageSize;
}

/// What the composition root hands over: the use cases, built once, the
/// settings and the few ports the screens read directly, the notices the user
/// is owed, and the controls of the demo (which exist in the development
/// configuration only).
final class AppContainer {
  /// Creates the container.
  new({
    required this.kind,
    required this.useCases,
    required this.settings,
    required this.clock,
    required this.monitoring,
    required this.screenProtection,
    required this.notices,
    this.demoControls,
    this._onDispose,
  });

  /// Which adapters the app is wired with.
  final AdaptersKind kind;

  /// Every use case, built once and shared.
  final UseCases useCases;

  /// The values the screens need that come from the configuration.
  final AppSettings settings;

  /// The clock the use cases read, for the screen that has to record an instant
  /// (the background): one instant is not read from two clocks.
  final Clock clock;

  /// Where the events go, for the screens that report one.
  final Monitoring monitoring;

  /// The screen protection the use cases drive, for the screen that mounts a
  /// protected view.
  final ScreenProtection screenProtection;

  /// What the user is owed an explanation of at the start.
  final AppNotices notices;

  /// What the demo drives: the switch of the simulated network and the accounts
  /// the sign-in screen offers. Null in the real configuration, which has
  /// neither.
  final DemoControls? demoControls;

  final Future<void> Function()? _onDispose;
  bool _disposed = false;

  /// Closes what the container opened (the database of the real
  /// configuration). Safe to call more than once; the container is not usable
  /// afterwards.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _onDispose?.call();
  }
}
