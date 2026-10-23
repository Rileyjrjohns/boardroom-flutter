import 'dart:async';

import 'package:boardroom/app/dev/in_memory/simulated_network.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/core/infrastructure/clock/sleep.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/infrastructure/sleep.dart';

SimulatedNetwork _network({Sleep? sleep, DurationMillis? latency}) =>
    SimulatedNetwork(
      sleep: sleep ?? immediateSleep,
      latency: latency ?? aDuration(0),
    );

void main() {
  group('SimulatedNetwork', () {
    test('is online by default, and lets a request in', () async {
      final network = _network();

      expect(network.online, isTrue);
      expect(await network.enter(), equals(ok<void>(null)));
    });

    test('goes offline and online again, as told', () async {
      final network = _network()..setOnline(online: false);

      expect(network.online, isFalse);
      expect(await network.enter(), equals(err(networkUnavailable())));
      network.setOnline(online: true);
      expect(network.online, isTrue);
      expect(await network.enter(), equals(ok<void>(null)));
    });

    test('waits for the latency before letting a request in, '
        'through the sleep it was given', () async {
      final (:sleep, :requested) = recordingSleep();
      final network = _network(sleep: sleep, latency: aDuration(250));

      await network.enter();

      expect(requested, equals([250]));
    });

    test('applies a latency set later', () async {
      final (:sleep, :requested) = recordingSleep();
      final network = _network(sleep: sleep)..setLatency(aDuration(900));
      await network.enter();

      expect(network.latency, equals(900));
      expect(requested, equals([900]));
    });

    test('times out a latency above the cap: it waits for the cap, '
        'no longer, and then fails', () async {
      final (:sleep, :requested) = recordingSleep();
      final network = _network(sleep: sleep, latency: aDuration(3600000));

      final result = await network.enter();

      expect(requested, equals([maxSimulatedLatencyMillis]));
      expect(result, equals(err(networkUnavailable())));
    });

    test('lets a latency that is exactly the cap through', () async {
      final (:sleep, :requested) = recordingSleep();
      final network = _network(
        sleep: sleep,
        latency: aDuration(maxSimulatedLatencyMillis),
      );

      expect(await network.enter(), equals(ok<void>(null)));
      expect(requested, equals([maxSimulatedLatencyMillis]));
    });

    for (final (name, sleep) in <(String, Sleep)>[
      ('throws', (millis) => throw StateError('timer is gone')),
      ('rejects', (millis) => Future<void>.error(StateError('timer is gone'))),
    ]) {
      test('answers networkUnavailable, and does not let the error escape, '
          'when the sleep $name', () async {
        final network = _network(sleep: sleep, latency: aDuration(250));

        expect(await network.enter(), equals(err(networkUnavailable())));
      });
    }

    test(
      'does not wait at all when offline: the failure is immediate',
      () async {
        final (:sleep, :requested) = recordingSleep();
        final network = _network(sleep: sleep, latency: aDuration(250))
          ..setOnline(online: false);

        await network.enter();

        expect(requested, isEmpty);
      },
    );

    test('fails a request in flight when the connection drops '
        'before its latency has elapsed', () async {
      final released = Completer<void>();
      final network = _network(
        sleep: (millis) => released.future,
        latency: aDuration(250),
      );

      final entering = network.enter();
      network.setOnline(online: false);
      released.complete();

      expect(await entering, equals(err(networkUnavailable())));
    });
  });

  group('SimulatedNetwork, in Dart', () {
    test('tells its subscribers when the connection goes off and comes back, '
        'and only then', () {
      final network = _network();
      final seen = <bool>[];
      final stop = network.subscribe(({required online}) => seen.add(online));

      network
        ..setOnline(online: true)
        ..setOnline(online: false)
        ..setOnline(online: false)
        ..setOnline(online: true);
      stop();
      network.setOnline(online: false);

      expect(seen, equals([false, true]));
    });

    test('goes on when a subscriber throws', () {
      final network = _network();
      final seen = <bool>[];
      network
        ..subscribe(({required online}) => throw StateError('a bug'))
        ..subscribe(({required online}) => seen.add(online))
        ..setOnline(online: false);

      expect(seen, equals([false]));
    });
  });
}
