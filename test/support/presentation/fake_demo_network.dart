import 'package:boardroom/core/presentation/demo/demo_controls.dart';

/// The switch of the simulated connection, for the tests of the demo
/// components.
final class FakeDemoNetwork implements DemoNetwork {
  bool _online = true;
  final List<void Function({required bool online})> _listeners = [];

  @override
  bool get online => _online;

  @override
  void setOnline({required bool online}) {
    _online = online;
    for (final listener in List.of(_listeners)) {
      listener(online: online);
    }
  }

  @override
  void Function() subscribe(void Function({required bool online}) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// Demo controls over a [FakeDemoNetwork], with no account.
DemoControls aDemoControls([FakeDemoNetwork? network]) =>
    DemoControls(network: network ?? FakeDemoNetwork(), accounts: const []);
