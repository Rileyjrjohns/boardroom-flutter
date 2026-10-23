import 'package:boardroom/application/ports/connectivity.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/infrastructure/connectivity/device_connectivity.dart';
import 'package:test/test.dart';

import '../../application/support/contracts/connectivity_contract.dart';
import '../../application/support/fake_monitoring.dart';
import '../support/fake_network_state.dart';

const ConnectivityStatus _online = ConnectivityStatus.online;
const ConnectivityStatus _offline = ConnectivityStatus.offline;

/// Lets what the adapter does in the background (reading the starting point)
/// finish.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// The report of the platform as JSON writes it: a flag it does not set is not
/// there.
String _json(NetworkSnapshot state) {
  final parts = [
    if (state.isConnected != null) '"isConnected":${state.isConnected}',
    if (state.isInternetReachable != null)
      '"isInternetReachable":${state.isInternetReachable}',
  ];
  return '{${parts.join(',')}}';
}

void main() {
  describeConnectivityContract('DeviceConnectivity', () {
    final platform = FakeNetworkState();
    return ConnectivityHarness(
      connectivity: DeviceConnectivity(
        api: platform,
        monitoring: FakeMonitoring(),
      ),
      report: (status) async {
        platform.change(
          status == _online
              ? const NetworkSnapshot(
                  isConnected: true,
                  isInternetReachable: true,
                )
              : const NetworkSnapshot(
                  isConnected: false,
                  isInternetReachable: false,
                ),
        );
        await _settle();
      },
    );
  });

  group('statusOf', () {
    for (final (state, status) in <(NetworkSnapshot, ConnectivityStatus)>[
      (
        const NetworkSnapshot(isConnected: true, isInternetReachable: true),
        _online,
      ),
      (
        const NetworkSnapshot(isConnected: false, isInternetReachable: false),
        _offline,
      ),
      (const NetworkSnapshot(isConnected: false), _offline),
      (
        const NetworkSnapshot(isConnected: true, isInternetReachable: false),
        _offline,
      ),
      (
        const NetworkSnapshot(isConnected: false, isInternetReachable: true),
        _offline,
      ),
      (const NetworkSnapshot(isConnected: true), _online),
      (const NetworkSnapshot(isInternetReachable: true), _online),
      (const NetworkSnapshot(), _online),
      (const NetworkSnapshot(), _online),
    ]) {
      test('reads ${_json(state)} as ${status.value}', () {
        expect(statusOf(state), equals(status));
      });
    }
  });

  group('DeviceConnectivity', () {
    ({
      FakeNetworkState platform,
      FakeMonitoring monitoring,
      DeviceConnectivity connectivity,
    })
    aConnectivity() {
      final platform = FakeNetworkState();
      final monitoring = FakeMonitoring();
      return (
        platform: platform,
        monitoring: monitoring,
        connectivity: DeviceConnectivity(
          api: platform,
          monitoring: monitoring,
          timeoutMillis: 20,
        ),
      );
    }

    test('is online when the platform cannot be asked, and when it does not '
        'answer in time', () async {
      final (:platform, :connectivity, monitoring: _) = aConnectivity();
      platform.failure = Exception('no module');
      expect(await connectivity.current(), equals(_online));

      platform
        ..failure = null
        ..hanging = true;
      expect(await connectivity.current(), equals(_online));
    });

    test(
      'listens to the platform once for any number of subscribers, and stops '
      'when the last one leaves',
      () async {
        final (:platform, :connectivity, monitoring: _) = aConnectivity();
        final stopFirst = connectivity.subscribe((_) {});
        final stopSecond = connectivity.subscribe((_) {});
        await _settle();

        expect(platform.subscriptions, equals(1));
        expect(platform.listeners, hasLength(1));

        stopFirst();
        expect(platform.listeners, hasLength(1));
        stopSecond();
        expect(platform.listeners, isEmpty);
      },
    );

    test(
      'starts listening again, and reads the starting point again, for a later '
      'subscriber',
      () async {
        final (:platform, :connectivity, monitoring: _) = aConnectivity();
        final first = <ConnectivityStatus>[];
        final stop = connectivity.subscribe(first.add);
        await _settle();
        stop();
        platform.state = const NetworkSnapshot(isConnected: false);

        final second = <ConnectivityStatus>[];
        connectivity.subscribe(second.add);
        await _settle();
        platform.change(
          const NetworkSnapshot(isConnected: false, isInternetReachable: false),
        );
        await _settle();
        platform.change(
          const NetworkSnapshot(isConnected: true, isInternetReachable: true),
        );
        await _settle();

        expect(platform.subscriptions, equals(2));
        expect(second, equals([_online]));
      },
    );

    test(
      'does not take a report of the platform that repeats what it said for a '
      'change',
      () async {
        final (:platform, :connectivity, monitoring: _) = aConnectivity();
        final received = <ConnectivityStatus>[];
        connectivity.subscribe(received.add);
        await _settle();

        platform
          ..change(const NetworkSnapshot(isConnected: true))
          ..change(
            const NetworkSnapshot(isConnected: true, isInternetReachable: true),
          )
          ..change(const NetworkSnapshot(isConnected: false))
          ..change(
            const NetworkSnapshot(
              isConnected: false,
              isInternetReachable: false,
            ),
          );
        await _settle();

        expect(received, equals([_offline]));
      },
    );

    test('knows the starting point when the first report comes before it has '
        'been read', () async {
      final (:platform, :connectivity, monitoring: _) = aConnectivity();
      platform.state = const NetworkSnapshot(isConnected: false);
      final received = <ConnectivityStatus>[];
      connectivity.subscribe(received.add);

      // The platform confirms what it said at the start, before the adapter
      // has read it.
      platform.change(const NetworkSnapshot(isConnected: false));
      await _settle();

      expect(received, isEmpty);
    });

    test(
      'drops a report that arrives after the last subscriber left',
      () async {
        final (:platform, :connectivity, monitoring: _) = aConnectivity();
        final received = <ConnectivityStatus>[];
        final stop = connectivity.subscribe(received.add);
        await _settle();

        platform.change(const NetworkSnapshot(isConnected: false));
        stop();
        await _settle();

        expect(received, isEmpty);
      },
    );

    test(
      'reports a listener that throws to the monitoring, once for each change, '
      'without a cause that says what it was',
      () async {
        final (:platform, :connectivity, :monitoring) = aConnectivity();
        final heard = <ConnectivityStatus>[];
        connectivity
          ..subscribe((_) => throw Exception('secret detail of the listener'))
          ..subscribe(heard.add);
        await _settle();

        platform.change(const NetworkSnapshot(isConnected: false));
        await _settle();
        platform.change(
          const NetworkSnapshot(isConnected: true, isInternetReachable: true),
        );
        await _settle();

        expect(heard, equals([_offline, _online]));
        expect(
          monitoring.capturedEvents(),
          equals([
            MonitoringEvent.connectivityListenerFailed,
            MonitoringEvent.connectivityListenerFailed,
          ]),
        );
        expect('${monitoring.errors}', isNot(contains('secret detail')));
      },
    );

    test(
      'keeps listening to the platform while one of two subscriptions of the '
      'same function is left',
      () async {
        final (:platform, :connectivity, monitoring: _) = aConnectivity();
        void listener(ConnectivityStatus status) {}
        final stopFirst = connectivity.subscribe(listener);
        final stopSecond = connectivity.subscribe(listener);
        await _settle();

        stopFirst();
        expect(platform.listeners, hasLength(1));
        stopSecond();

        expect(platform.listeners, isEmpty);
      },
    );
  });
}
