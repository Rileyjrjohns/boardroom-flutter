import 'package:boardroom/application/ports/types/unsubscribe.dart';
import 'package:boardroom/domain/shared/constants.dart';

/// Whether the device has a connection, as far as the platform can tell.
enum ConnectivityStatus implements StableValue {
  /// The device has a connection, or the platform cannot say.
  online('online'),

  /// The device reports that it has no connection.
  offline('offline');

  new(this.value);

  @override
  final String value;
}

/// What the device says about its connection. It is a hint and never the truth:
/// the answer of a remote call is. A device that reports `online` may still
/// fail to reach the server, and one that reports `offline` may be about to
/// recover, so the offline policy (`loadWithCacheFallback`) goes by the error
/// of the call and not by this port. What the port is for is to tell the
/// presentation when to show that the device is offline, and when to trigger
/// `SyncPendingVotes` (on a change to `online`): the application layer does not
/// watch the network by itself.
///
/// Contract:
/// - No method throws, and `current` settles in bounded time.
/// - When the platform cannot say, the status is `online`: the calls then
///   answer for themselves, and an app that wrongly says `offline` for ever
///   would be worse than one that tries and fails.
/// - `subscribe` does not call the listener when it subscribes (ask `current`
///   for the starting point). It calls it for each change of the status after
///   that, never twice in a row with the same status, until the returned
///   function is called. Calling that function again does nothing, and it does
///   not affect the other subscribers. A listener must not throw.
abstract interface class Connectivity {
  /// The status of the connection now.
  Future<ConnectivityStatus> current();

  /// Calls [listener] for each change of the status, until the returned
  /// function is called.
  Unsubscribe subscribe(void Function(ConnectivityStatus status) listener);
}
