import 'package:boardroom/app/composition/ports.dart';
import 'package:boardroom/core/presentation/demo/demo_controls.dart';
import 'package:boardroom/core/presentation/notices/app_notices.dart';
import 'package:meta/meta.dart';

/// What a configuration builds before the use cases are wired: the ports, and
/// what the container hands over besides them.
@immutable
final class Wiring {
  /// Creates the result of a configuration.
  const new({
    required this.ports,
    required this.startsLocked,
    required this.notices,
    this.demoControls,
    this.onDispose,
  });

  /// An adapter for every port.
  final Ports ports;

  /// Whether the app starts locked. A real start is a cold start, so it is. A
  /// configuration that opened a session by itself stands for a sign-in the
  /// user has just made, so it is not.
  final bool startsLocked;

  /// What the user is owed an explanation of at the start.
  final AppNotices notices;

  /// The controls of the demo; only the development configuration has them.
  final DemoControls? demoControls;

  /// Closes what the configuration opened, if anything.
  final Future<void> Function()? onDispose;
}
