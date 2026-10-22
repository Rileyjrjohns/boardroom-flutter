import 'package:boardroom/application/ports/screen_protection.dart';
import 'package:boardroom/application/shared/screen_protection_coordinator.dart';

/// The deps of a `ScreenProtectionCoordinator` built by hand: a switch and
/// nothing else, as the React Native tests pass `{ screenProtection }`.
final class ScreenProtectionDeps implements ScreenProtectionCoordinatorDeps {
  /// Wraps [screenProtection].
  const new(this.screenProtection);

  @override
  final ScreenProtection screenProtection;
}
