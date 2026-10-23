import 'package:boardroom/app/dev/in_memory/simulated_network.dart';
import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/application/ports/types/unsubscribe.dart';

ConnectivityStatus _statusOf({required bool online}) =>
    online ? ConnectivityStatus.online : ConnectivityStatus.offline;

/// The connectivity of the mock configuration: the device is online when the
/// simulated server is reachable. It listens to the same switch the three
/// repositories and the sign-in go through, so that the offline switch of the
/// demo drives the whole app, the banner and the sync included, with nothing
/// native and nothing random.
final class SimulatedConnectivity implements Connectivity {
  /// Creates the connectivity that follows the `network`.
  const new(this._network);

  final NetworkControl _network;

  @override
  Future<ConnectivityStatus> current() async =>
      _statusOf(online: _network.online);

  @override
  Unsubscribe subscribe(void Function(ConnectivityStatus status) listener) =>
      _network.subscribe(({required online}) {
        listener(_statusOf(online: online));
      });
}
