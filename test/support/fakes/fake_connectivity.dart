import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/application/ports/types/unsubscribe.dart';

// Each subscription is an object of its own, so the same function can
// subscribe twice.
class _Subscription {
  const new(this.listener);

  final void Function(ConnectivityStatus status) listener;
}

/// A device that is online until the test says otherwise.
class FakeConnectivity implements Connectivity {
  ConnectivityStatus _status = ConnectivityStatus.online;
  final Set<_Subscription> _subscriptions = {};

  /// How many times `current` was asked.
  int currentCalls = 0;

  @override
  Future<ConnectivityStatus> current() async {
    currentCalls += 1;
    return _status;
  }

  @override
  Unsubscribe subscribe(void Function(ConnectivityStatus status) listener) {
    final subscription = _Subscription(listener);
    _subscriptions.add(subscription);
    return () {
      _subscriptions.remove(subscription);
    };
  }

  /// The platform reports a status. Only a change is passed on, as the port
  /// promises.
  void emit(ConnectivityStatus status) {
    if (status == _status) {
      return;
    }
    _status = status;
    for (final subscription in List.of(_subscriptions)) {
      try {
        subscription.listener(status);
        // A listener that throws does not stop the others hearing the change:
        // the port says so.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
  }

  /// How many listeners are subscribed.
  int get listenerCount => _subscriptions.length;
}
