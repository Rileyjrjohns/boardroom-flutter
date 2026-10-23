import 'dart:async';

import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:test/test.dart';

/// What the suite needs besides the port.
final class ConnectivityHarness {
  /// Creates a harness.
  const new({required this.connectivity, required this.report});

  /// The adapter under test.
  final Connectivity connectivity;

  /// Makes the device report this status, the way the platform would. Online at
  /// first.
  final FutureOr<void> Function(ConnectivityStatus status) report;
}

/// Makes a harness, now or later.
typedef ConnectivityFactory = FutureOr<ConnectivityHarness> Function();

const ConnectivityStatus _online = ConnectivityStatus.online;
const ConnectivityStatus _offline = ConnectivityStatus.offline;

/// The contract of `Connectivity`, as a suite any implementation runs: the
/// status it reports, the changes it announces (and only changes), and
/// subscriptions that stop on their own, each one a handle of its own, whose
/// listener cannot hurt the others by throwing. The factory returns a device
/// that is online and has no subscriber.
void describeConnectivityContract(
  String name,
  ConnectivityFactory createHarness,
) {
  group('$name honours the Connectivity contract', () {
    late ConnectivityHarness harness;
    late Connectivity connectivity;

    setUp(() async {
      harness = await createHarness();
      connectivity = harness.connectivity;
    });

    test('reports the status of the device, now', () async {
      expect(await connectivity.current(), equals(_online));

      await harness.report(_offline);
      expect(await connectivity.current(), equals(_offline));

      await harness.report(_online);
      expect(await connectivity.current(), equals(_online));
    });

    test('does not call a listener when it subscribes', () async {
      final received = <ConnectivityStatus>[];

      connectivity.subscribe(received.add);
      await connectivity.current();

      expect(received, equals(<ConnectivityStatus>[]));
    });

    test('calls a listener for each change, in order', () async {
      final received = <ConnectivityStatus>[];
      connectivity.subscribe(received.add);

      await harness.report(_offline);
      await harness.report(_online);
      await harness.report(_offline);

      expect(received, equals([_offline, _online, _offline]));
    });

    test(
      'does not call a listener twice in a row with the same status',
      () async {
        final received = <ConnectivityStatus>[];
        connectivity.subscribe(received.add);

        await harness.report(_online);
        await harness.report(_offline);
        await harness.report(_offline);
        await harness.report(_online);
        await harness.report(_online);

        expect(received, equals([_offline, _online]));
      },
    );

    test('calls every subscriber, and stops each one on its own', () async {
      final first = <ConnectivityStatus>[];
      final second = <ConnectivityStatus>[];
      final stopFirst = connectivity.subscribe(first.add);
      connectivity.subscribe(second.add);

      await harness.report(_offline);
      stopFirst();
      await harness.report(_online);

      expect(first, equals([_offline]));
      expect(second, equals([_offline, _online]));
    });

    test('lets a subscriber unsubscribe twice '
        'without harm to the others', () async {
      final kept = <ConnectivityStatus>[];
      final stop = connectivity.subscribe((_) {});
      connectivity.subscribe(kept.add);

      stop();
      stop();
      await harness.report(_offline);

      expect(kept, equals([_offline]));
    });

    test('makes a subscription of its own each time, '
        'even for the same function', () async {
      final received = <ConnectivityStatus>[];
      void listener(ConnectivityStatus status) => received.add(status);
      final stopFirst = connectivity.subscribe(listener);
      connectivity.subscribe(listener);

      await harness.report(_offline);
      stopFirst();
      await harness.report(_online);

      expect(received, equals([_offline, _offline, _online]));
    });

    test('lets a function that subscribed twice stop one subscription twice '
        'without stopping the other', () async {
      final received = <ConnectivityStatus>[];
      void listener(ConnectivityStatus status) => received.add(status);
      final stopFirst = connectivity.subscribe(listener);
      connectivity.subscribe(listener);

      stopFirst();
      stopFirst();
      await harness.report(_offline);

      expect(received, equals([_offline]));
    });

    test('does not let a listener that throws stop the others '
        'hearing the change, nor escape', () async {
      final before = <ConnectivityStatus>[];
      final after = <ConnectivityStatus>[];
      connectivity
        ..subscribe(before.add)
        ..subscribe((_) {
          throw StateError('broken listener');
        })
        ..subscribe(after.add);

      await expectLater(
        Future<void>.sync(() => harness.report(_offline)),
        completion(isNull),
      );
      await harness.report(_online);

      expect(before, equals([_offline, _online]));
      expect(after, equals([_offline, _online]));
    });

    test('lets the status change when nobody listens', () async {
      await harness.report(_offline);

      expect(await connectivity.current(), equals(_offline));
    });
  });
}
