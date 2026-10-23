import 'package:boardroom/application/ports/types/unsubscribe.dart';
import 'package:boardroom/infrastructure/connectivity/device_connectivity.dart';
import 'package:connectivity_plus/connectivity_plus.dart' as plus;

/// What `connectivity_plus` reports as a [NetworkSnapshot]: connected when it
/// lists a connection other than `none` (it reports `none` alone when there is
/// no connection). The plugin tells which radio is up, not whether it reaches
/// the internet, so `isInternetReachable` is left unset, which says nothing
/// (see `statusOf`).
NetworkSnapshot snapshotOf(Iterable<plus.ConnectivityResult> results) =>
    NetworkSnapshot(
      isConnected: results.any(
        (result) => result != plus.ConnectivityResult.none,
      ),
    );

/// The two calls of `connectivity_plus` that the connectivity uses, handed
/// over as they are. No logic of its own besides [snapshotOf], so the tests
/// only check that it asks the plugin the right questions, and the events of
/// the platform have been received on no device.
final class ConnectivityPlusNetworkState implements NetworkStateApi {
  /// Creates the adapter over [connectivity], the plugin by default.
  new([plus.Connectivity? connectivity])
    : _connectivity = connectivity ?? plus.Connectivity();

  final plus.Connectivity _connectivity;

  @override
  Future<NetworkSnapshot> getState() async =>
      snapshotOf(await _connectivity.checkConnectivity());

  @override
  Unsubscribe subscribe(void Function(NetworkSnapshot state) listener) {
    final subscription = _connectivity.onConnectivityChanged.listen(
      (results) => listener(snapshotOf(results)),
    );
    return () {
      // The cancellation has nothing to report: the listener is gone.
      subscription.cancel().ignore();
    };
  }
}
