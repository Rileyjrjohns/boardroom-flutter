import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/core/infrastructure/connectivity/device_connectivity.dart';

// Test support, not production code: the state of the network as the platform
// reports it, which a test changes and which tells its listeners, like the
// platform does.

/// A network state a test drives.
final class FakeNetworkState implements NetworkStateApi {
  /// What `getState` answers.
  NetworkSnapshot state = const NetworkSnapshot(
    isConnected: true,
    isInternetReachable: true,
  );

  /// Makes `getState` fail with this while set.
  Object? failure;

  /// Makes `getState` never answer while set.
  bool hanging = false;

  /// The listeners the platform tells.
  final Set<void Function(NetworkSnapshot state)> listeners = {};

  /// How many times the platform was listened to.
  int subscriptions = 0;

  @override
  Future<NetworkSnapshot> getState() {
    if (hanging) {
      return Future<NetworkSnapshot>.delayed(const Duration(days: 1));
    }
    final error = failure;
    return error == null ? Future.value(state) : Future.error(error);
  }

  @override
  Unsubscribe subscribe(void Function(NetworkSnapshot state) listener) {
    subscriptions += 1;
    listeners.add(listener);
    return () {
      listeners.remove(listener);
    };
  }

  /// The platform changes state and says so.
  void change(NetworkSnapshot next) {
    state = next;
    for (final listener in List.of(listeners)) {
      listener(next);
    }
  }
}
