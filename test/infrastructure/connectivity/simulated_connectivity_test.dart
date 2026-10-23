import 'package:boardroom/application/ports/connectivity.dart';
import 'package:boardroom/infrastructure/connectivity/simulated_connectivity.dart';
import 'package:boardroom/infrastructure/in_memory/simulated_network.dart';
import 'package:test/test.dart';

import '../../application/support/contracts/connectivity_contract.dart';
import '../../domain/support/builders.dart';
import '../support/sleep.dart';

SimulatedNetwork _aNetwork() =>
    SimulatedNetwork(sleep: immediateSleep, latency: aDuration(0));

void main() {
  describeConnectivityContract('SimulatedConnectivity', () {
    final network = _aNetwork();
    return ConnectivityHarness(
      connectivity: SimulatedConnectivity(network),
      report: (status) =>
          network.setOnline(online: status == ConnectivityStatus.online),
    );
  });

  group('SimulatedConnectivity', () {
    test(
      'follows the switch of the simulated server, whoever turns it',
      () async {
        final network = _aNetwork();
        final connectivity = SimulatedConnectivity(network);
        final received = <ConnectivityStatus>[];
        connectivity.subscribe(received.add);

        network.setOnline(online: false);

        expect(
          await connectivity.current(),
          equals(ConnectivityStatus.offline),
        );
        expect(received, equals([ConnectivityStatus.offline]));
      },
    );
  });
}
