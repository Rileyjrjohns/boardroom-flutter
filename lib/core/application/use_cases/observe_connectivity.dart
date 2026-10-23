import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/application/ports/types/unsubscribe.dart';

/// What [ObserveConnectivity] needs.
abstract interface class ObserveConnectivityDeps {
  /// The connectivity of the device.
  Connectivity get connectivity;
}

/// Where the connection stands now, and how to stop hearing about its changes.
final class ConnectivityObservation {
  /// Creates an observation.
  const new({required this.status, required this.unsubscribe});

  /// The status when the observation started, including any change that came
  /// while it started.
  final ConnectivityStatus status;

  /// Stops the observation. Calling it again does nothing.
  final Unsubscribe unsubscribe;
}

/// Watches the connectivity of the device. The caller gets the status at the
/// start, then each later change through `onChange`, and stops with
/// `unsubscribe`. It needs no session: the sign-in screen is as interested in
/// being offline as the meetings are.
///
/// The subscription starts before the status is read, so that a change that
/// happens in between is not missed: it replaces the status read, which is
/// older. Only a change is reported, a status that repeats is not, whatever the
/// adapter does. The application does not decide what a change means: the
/// presentation shows it and calls `SyncPendingVotes` when the connection comes
/// back.
final class ObserveConnectivity {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final ObserveConnectivityDeps _deps;

  /// Starts watching; [onChange] receives each change after the start.
  Future<ConnectivityObservation> execute(
    void Function(ConnectivityStatus status) onChange,
  ) async {
    final connectivity = _deps.connectivity;
    ConnectivityStatus? latest;
    var starting = true;
    var active = true;

    final stopListening = connectivity.subscribe((status) {
      if (!active || status == latest) {
        return;
      }
      latest = status;
      if (!starting) {
        onChange(status);
      }
    });

    final read = await connectivity.current();
    final status = latest ??= read;
    starting = false;

    return ConnectivityObservation(
      status: status,
      unsubscribe: () {
        if (!active) {
          return;
        }
        active = false;
        stopListening();
      },
    );
  }
}
