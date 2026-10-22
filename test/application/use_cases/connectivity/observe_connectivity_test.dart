import 'dart:async';

import 'package:boardroom/application/ports/connectivity.dart';
import 'package:boardroom/application/ports/types/unsubscribe.dart';
import 'package:boardroom/application/use_cases/connectivity/observe_connectivity.dart';
import 'package:test/test.dart';

import '../../support/create_fakes.dart';

/// The one fake [ObserveConnectivity] needs, out of the whole set (or a
/// connectivity written by the test).
final class _Deps implements ObserveConnectivityDeps {
  const new(this.connectivity);

  @override
  final Connectivity connectivity;
}

/// A connectivity whose two operations are the functions the test gives.
final class _ScriptedConnectivity implements Connectivity {
  const new({required this.onCurrent, required this.onSubscribe});

  final Future<ConnectivityStatus> Function() onCurrent;
  final Unsubscribe Function(void Function(ConnectivityStatus status) listener)
  onSubscribe;

  @override
  Future<ConnectivityStatus> current() => onCurrent();

  @override
  Unsubscribe subscribe(void Function(ConnectivityStatus status) listener) =>
      onSubscribe(listener);
}

const ConnectivityStatus _online = ConnectivityStatus.online;
const ConnectivityStatus _offline = ConnectivityStatus.offline;

({
  Fakes fakes,
  List<ConnectivityStatus> received,
  Future<ConnectivityObservation> Function() observe,
})
_observer() {
  final fakes = createFakes();
  final received = <ConnectivityStatus>[];
  Future<ConnectivityObservation> observe() =>
      ObserveConnectivity(fakes).execute(received.add);
  return (fakes: fakes, received: received, observe: observe);
}

void main() {
  group('ObserveConnectivity', () {
    test('starts from the status of the device, without announcing it as a '
        'change', () async {
      final (:fakes, :received, :observe) = _observer();
      fakes.connectivity.emit(_offline);

      final observation = await observe();

      expect(observation.status, equals(_offline));
      expect(received, equals(<ConnectivityStatus>[]));
    });

    test('announces each change after the start, in order', () async {
      final (:fakes, :received, :observe) = _observer();
      await observe();

      fakes.connectivity.emit(_offline);
      fakes.connectivity.emit(_online);

      expect(received, equals([_offline, _online]));
    });

    test('does not announce a status that repeats, whatever the adapter '
        'does', () async {
      final received = <ConnectivityStatus>[];
      late void Function(ConnectivityStatus status) report;
      final noisy = _ScriptedConnectivity(
        onCurrent: () async => _online,
        onSubscribe: (listener) {
          report = listener;
          return () {};
        },
      );
      await ObserveConnectivity(_Deps(noisy)).execute(received.add);

      report(_online);
      report(_offline);
      report(_offline);
      report(_online);

      expect(received, equals([_offline, _online]));
    });

    test('starts listening before it reads the status, so that no change is '
        'missed', () async {
      final received = <ConnectivityStatus>[];
      late void Function(ConnectivityStatus status) report;
      final answer = Completer<ConnectivityStatus>();
      final slow = _ScriptedConnectivity(
        onCurrent: () => answer.future,
        onSubscribe: (listener) {
          report = listener;
          return () {};
        },
      );
      final started = ObserveConnectivity(_Deps(slow)).execute(received.add);

      // The device goes offline while the status is being read; the read
      // answers with the old one.
      report(_offline);
      answer.complete(_online);
      final observation = await started;

      expect(observation.status, equals(_offline));
      expect(received, equals(<ConnectivityStatus>[]));
    });

    test('stops announcing once it is unsubscribed, which can be done '
        'twice', () async {
      final (:fakes, :received, :observe) = _observer();
      final observation = await observe();

      fakes.connectivity.emit(_offline);
      observation.unsubscribe();
      observation.unsubscribe();
      fakes.connectivity.emit(_online);

      expect(received, equals([_offline]));
      expect(fakes.connectivity.listenerCount, equals(0));
    });

    test('unsubscribes from the port once, not once per call', () async {
      var unsubscribed = 0;
      final counting = _ScriptedConnectivity(
        onCurrent: () async => _online,
        onSubscribe: (_) => () {
          unsubscribed += 1;
        },
      );
      final observation = await ObserveConnectivity(_Deps(counting))
          .execute((_) {});

      observation.unsubscribe();
      observation.unsubscribe();

      expect(unsubscribed, equals(1));
    });

    test('keeps independent observations apart', () async {
      final (:fakes, :received, :observe) = _observer();
      final first = await observe();
      await observe();

      first.unsubscribe();
      fakes.connectivity.emit(_offline);

      expect(received, equals([_offline]));
    });
  });
}
