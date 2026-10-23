import 'dart:async';

import 'package:boardroom/core/infrastructure/connectivity/connectivity_plus_network_state.dart';
import 'package:boardroom/core/infrastructure/connectivity/device_connectivity.dart';
import 'package:connectivity_plus/connectivity_plus.dart' as plus;
import 'package:flutter_test/flutter_test.dart';

/// `connectivity_plus` with a state the test sets and events it sends.
final class _FakeConnectivityPlus implements plus.Connectivity {
  List<plus.ConnectivityResult> results = const [plus.ConnectivityResult.wifi];
  final StreamController<List<plus.ConnectivityResult>> events =
      StreamController.broadcast();

  @override
  Future<List<plus.ConnectivityResult>> checkConnectivity() async => results;

  @override
  Stream<List<plus.ConnectivityResult>> get onConnectivityChanged =>
      events.stream;
}

void main() {
  group('ConnectivityPlusNetworkState', () {
    test('hands over the state the module reports', () async {
      final module = _FakeConnectivityPlus()
        ..results = const [plus.ConnectivityResult.mobile];

      expect(
        await ConnectivityPlusNetworkState(module).getState(),
        equals(const NetworkSnapshot(isConnected: true)),
      );
    });

    test(
      'passes the events of the module to the listener until it is stopped',
      () async {
        final module = _FakeConnectivityPlus();
        final received = <NetworkSnapshot>[];
        final stop = ConnectivityPlusNetworkState(module)
            .subscribe(received.add);

        module.events.add(const [plus.ConnectivityResult.none]);
        await Future<void>.delayed(Duration.zero);
        stop();
        expect(module.events.hasListener, isFalse);
        module.events.add(const [plus.ConnectivityResult.wifi]);
        await Future<void>.delayed(Duration.zero);

        expect(received, equals([const NetworkSnapshot(isConnected: false)]));
      },
    );

    group('snapshotOf', () {
      for (final (name, results, connected)
          in <(String, List<plus.ConnectivityResult>, bool)>[
            ('no connection', const [plus.ConnectivityResult.none], false),
            ('wifi', const [plus.ConnectivityResult.wifi], true),
            ('a mobile network', const [plus.ConnectivityResult.mobile], true),
            (
              'several connections',
              const [plus.ConnectivityResult.wifi, plus.ConnectivityResult.vpn],
              true,
            ),
          ]) {
        test('reads $name as connected = $connected and says nothing about '
            'the internet', () {
          expect(
            snapshotOf(results),
            equals(NetworkSnapshot(isConnected: connected)),
          );
        });
      }
    });
  });
}
