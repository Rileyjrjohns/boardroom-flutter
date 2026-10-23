import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:meta/meta.dart';

/// The connection of the simulated server, which the demo switches off and on.
/// The development configuration hands one over; a real device has no switch
/// to cut its own network, so the http configuration has none.
abstract interface class DemoNetwork {
  /// Whether the simulated server answers.
  bool get online;

  /// Cuts the simulated server (`online: false`) or restores it.
  void setOnline({required bool online});

  /// Calls [listener] each time the connection goes off or comes back. Returns
  /// what stops it.
  Unsubscribe subscribe(void Function({required bool online}) listener);
}

/// An account of the simulated server, as the sign-in screen of the demo offers
/// it. The password of a simulated account protects nothing: it is shown to
/// whoever runs the demo.
@immutable
final class DemoAccountHint {
  /// Creates the hint of an account.
  const new({
    required this.fullName,
    required this.email,
    required this.password,
  });

  /// The name shown on the button of the account.
  final String fullName;

  /// The email address that fills the form.
  final String email;

  /// The password that fills the form.
  final String password;

  @override
  bool operator ==(Object other) =>
      other is DemoAccountHint &&
      other.fullName == fullName &&
      other.email == email &&
      other.password == password;

  @override
  int get hashCode => Object.hash(fullName, email, password);
}

/// What the demo drives: the connection of the simulated server and the
/// accounts of the simulation. They exist in the development configuration
/// only; the demo components render nothing without them.
@immutable
final class DemoControls {
  /// Creates the controls of the demo.
  const new({required this.network, required this.accounts});

  /// The switch of the simulated connection.
  final DemoNetwork network;

  /// The accounts the sign-in screen offers.
  final List<DemoAccountHint> accounts;
}
