import 'dart:math';

import 'package:boardroom/application/ports/types/unsubscribe.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:boardroom/infrastructure/clock/sleep.dart';
import 'package:boardroom/infrastructure/shared/subscribers.dart';

/// The longest a request is made to wait, whatever latency is configured. Every
/// port settles in bounded time, so a simulated server may be slow but never
/// stuck: a latency above the cap is a request that times out, and fails with
/// `networkUnavailable` once the cap has elapsed.
const int maxSimulatedLatencyMillis = 10000;

/// What the demo and the end-to-end tests drive: the connectivity of the
/// simulated server.
abstract interface class NetworkControl {
  /// Whether the simulated server can be reached.
  bool get online;

  /// How long a request takes to be answered, as configured.
  DurationMillis get latency;

  /// Cuts the connection or brings it back.
  void setOnline({required bool online});

  /// Sets how long a request takes to be answered.
  void setLatency(DurationMillis latency);

  /// Calls [listener] each time the connection goes off or comes back. Returns
  /// the function that stops it.
  Unsubscribe subscribe(void Function({required bool online}) listener);
}

/// The connectivity of the simulated server: on or off, and how long it takes
/// to answer. It belongs to the server side of the simulation: the backend
/// exposes it, and every client of that server (the three repositories, the
/// sign-in) enters the network through it, so that going offline cuts them all
/// at once and deterministically. It starts online.
///
/// Going offline fails a request at once, like a device that knows it has no
/// connection. A request in flight when the connection drops fails too, when
/// its latency has elapsed. A latency above [maxSimulatedLatencyMillis] is a
/// timeout, and a [Sleep] that throws or fails is a network that failed: both
/// answer `networkUnavailable`, nothing escapes the port.
final class SimulatedNetwork implements NetworkControl {
  /// Creates a network that waits for `latency` through `sleep`. The tests give
  /// a `sleep` that does not wait.
  new({required this._sleep, required this._latency});

  bool _online = true;
  DurationMillis _latency;

  // A listener that throws is its own bug: the simulation goes on, and the
  // others are told.
  final Subscribers<bool> _subscribers = createSubscribers<bool>((_) {});
  final Sleep _sleep;

  @override
  bool get online => _online;

  @override
  DurationMillis get latency => _latency;

  @override
  void setOnline({required bool online}) {
    if (online == _online) {
      return;
    }
    _online = online;
    _subscribers.notify(online);
  }

  @override
  Unsubscribe subscribe(void Function({required bool online}) listener) =>
      _subscribers.subscribe((online) => listener(online: online));

  @override
  void setLatency(DurationMillis latency) {
    _latency = latency;
  }

  /// A client's request reaching the server: `networkUnavailable` when there is
  /// no connection, now or by the time the latency has elapsed, when the
  /// latency is a timeout, or when waiting failed; success otherwise.
  Future<Result<void, NetworkUnavailableError>> enter() async {
    if (!_online) {
      return err(networkUnavailable());
    }
    try {
      await _sleep(min(_latency, maxSimulatedLatencyMillis));
    } on Object {
      return err(networkUnavailable());
    }
    final timedOut = _latency > maxSimulatedLatencyMillis;
    if (!_online || timedOut) {
      return err(networkUnavailable());
    }
    return ok<void>(null);
  }
}
