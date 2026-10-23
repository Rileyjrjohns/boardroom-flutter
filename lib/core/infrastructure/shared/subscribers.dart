import 'package:boardroom/core/application/ports/types/unsubscribe.dart';

/// A set of listeners to call with a value, each subscription being a handle
/// of its own.
abstract interface class Subscribers<T> {
  /// Adds a listener. The function returned removes this subscription and no
  /// other: the same function subscribed twice is two subscriptions, called
  /// twice, and removing one leaves the other. Removing a subscription again
  /// does nothing.
  Unsubscribe subscribe(void Function(T value) listener);

  /// Calls every listener with the value, in the order they subscribed. A
  /// listener that throws is reported to `onError` and does not stop the
  /// others, nor does it escape. A listener that subscribes or unsubscribes
  /// while this runs takes effect for the next value.
  void notify(T value);

  /// How many subscriptions there are.
  int get size;
}

/// The listeners of an adapter: see [Subscribers].
Subscribers<T> createSubscribers<T>(void Function(Object error) onError) =>
    _Subscribers<T>(onError);

final class _Subscription<T> {
  const new(this.listener);

  final void Function(T value) listener;
}

final class _Subscribers<T> implements Subscribers<T> {
  new(this._onError);

  final void Function(Object error) _onError;
  final List<_Subscription<T>> _subscriptions = [];

  @override
  Unsubscribe subscribe(void Function(T value) listener) {
    final subscription = _Subscription<T>(listener);
    _subscriptions.add(subscription);
    return () {
      _subscriptions.remove(subscription);
    };
  }

  @override
  void notify(T value) {
    for (final subscription in List.of(_subscriptions)) {
      try {
        subscription.listener(value);
      } on Object catch (error) {
        _onError(error);
      }
    }
  }

  @override
  int get size => _subscriptions.length;
}
