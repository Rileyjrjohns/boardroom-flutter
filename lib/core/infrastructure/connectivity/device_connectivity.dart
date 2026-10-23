import 'dart:async';

import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/shared/attempt.dart';
import 'package:boardroom/core/infrastructure/shared/subscribers.dart';
import 'package:meta/meta.dart';

/// How long the platform may take to say where the connection stands.
const int defaultNetworkStateTimeoutMillis = 5000;

/// What the platform says about the connection: the two flags that matter.
/// A flag the platform does not set is `null`, and says nothing.
@immutable
final class NetworkSnapshot {
  /// Creates a report of the platform.
  const new({this.isConnected, this.isInternetReachable});

  /// Whether the device is connected to a network.
  final bool? isConnected;

  /// Whether that network reaches the internet.
  final bool? isInternetReachable;

  @override
  bool operator ==(Object other) =>
      other is NetworkSnapshot &&
      other.isConnected == isConnected &&
      other.isInternetReachable == isInternetReachable;

  @override
  int get hashCode => Object.hash(isConnected, isInternetReachable);

  @override
  String toString() =>
      'NetworkSnapshot(isConnected: $isConnected, '
      'isInternetReachable: $isInternetReachable)';
}

/// What the adapter asks of the platform.
abstract interface class NetworkStateApi {
  /// Where the connection stands now.
  Future<NetworkSnapshot> getState();

  /// Calls [listener] with the new state at each change. Returns the function
  /// that stops it.
  Unsubscribe subscribe(void Function(NetworkSnapshot state) listener);
}

/// `offline` when the platform says the device is not connected, or is
/// connected to a network that does not reach the internet. A flag the platform
/// does not set (`null`, which is how some devices answer at the start) says
/// nothing, and so is not a reason to call the device offline: the port
/// promises `online` when the platform cannot say.
ConnectivityStatus statusOf(NetworkSnapshot state) =>
    state.isConnected == false || state.isInternetReachable == false
    ? ConnectivityStatus.offline
    : ConnectivityStatus.online;

/// The connectivity of the device, over the platform layer
/// ([NetworkStateApi]). It listens to the platform once, however many
/// subscribers there are, and only while there is one. It tells its subscribers
/// about changes of the status, not about each report of the platform, which
/// repeats itself: the starting point is read when the first subscriber
/// arrives, and a report that says what is already known is dropped. A platform
/// that cannot be asked is `online` (see the port).
///
/// Every call of `subscribe` is a subscription of its own, even for the same
/// function, and a listener that throws is captured by the monitoring and does
/// not stop the others from hearing the change (`createSubscribers`).
final class DeviceConnectivity implements Connectivity {
  /// Creates the adapter over [api]. [monitoring] is told when a listener
  /// throws, which it must not. [timeoutMillis] defaults to
  /// [defaultNetworkStateTimeoutMillis].
  new({
    required this.api,
    required this.monitoring,
    this.timeoutMillis = defaultNetworkStateTimeoutMillis,
  }) {
    _subscribers = createSubscribers<ConnectivityStatus>((error) {
      monitoring.captureError(
        MonitoringEvent.connectivityListenerFailed,
        unexpected(describeFailure(error)),
      );
    });
  }

  /// What the adapter asks of the platform.
  final NetworkStateApi api;

  /// Told when a listener throws.
  final Monitoring monitoring;

  /// How long the platform may take to answer `current`.
  final int timeoutMillis;

  late final Subscribers<ConnectivityStatus> _subscribers;
  ConnectivityStatus? _known;
  Unsubscribe? _stopListening;

  // Settles when the starting point is known. Never fails.
  Future<void> _priming = Future.value();

  @override
  Future<ConnectivityStatus> current() async {
    final state = await attempt(api.getState, timeoutMillis);
    return switch (state) {
      Ok(:final value) => statusOf(value),
      Err() => ConnectivityStatus.online,
    };
  }

  @override
  Unsubscribe subscribe(void Function(ConnectivityStatus status) listener) {
    final stopSubscription = _subscribers.subscribe(listener);
    if (_stopListening == null) {
      _start();
    }
    return () {
      stopSubscription();
      if (_subscribers.size == 0) {
        _stop();
      }
    };
  }

  void _start() {
    _priming = current().then((status) {
      _known ??= status;
    });
    // The platform is listened to at once, so that no change is missed while
    // the starting point is being read; a report waits for it, to know whether
    // it is a change.
    _stopListening = api.subscribe((state) {
      final status = statusOf(state);
      unawaited(_priming.then((_) => _report(status)));
    });
  }

  void _stop() {
    _stopListening?.call();
    _stopListening = null;
    _known = null;
  }

  void _report(ConnectivityStatus status) {
    if (_stopListening == null || status == _known) {
      return;
    }
    _known = status;
    _subscribers.notify(status);
  }
}
