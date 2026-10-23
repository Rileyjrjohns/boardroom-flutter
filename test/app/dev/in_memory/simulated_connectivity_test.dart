import 'package:boardroom/app/dev/in_memory/simulated_connectivity.dart';
import 'package:boardroom/app/dev/in_memory/simulated_network.dart';
import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/contracts/connectivity_contract.dart';
import '../../../support/infrastructure/sleep.dart';

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
