import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/app/container/create_container.dart';
import 'package:boardroom/app/container/monitoring.dart';
import 'package:boardroom/app/container/runtime.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/core/infrastructure/monitoring/console_monitoring.dart';
import 'package:boardroom/core/infrastructure/monitoring/sentry_monitoring.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/builders/builders.dart';
import '../../support/fakes/fake_clock.dart';
import '../../support/fakes/fake_monitoring.dart';
import '../../support/infrastructure/fixture_files.dart';
import '../../support/infrastructure/memory_file_volume.dart';
import '../../support/infrastructure/sleep.dart';
import 'container_support.dart';

// The scenarios of `createMonitoring.test.ts` that belong to the composition:
// which adapter the monitoring is. What Sentry does with the events is tested
// with its adapter (test/core/infrastructure/monitoring). The SDK is disabled
// in this project (docs/monitoring.md), so an address with no SDK is the
// console.

const String _dsn =
    'https://0123456789abcdef@o123456.ingest.sentry.io/4500000000';

/// A stand-in for the SDK that records how it was started.
final class _RecordingSdk implements SentrySdk {
  new({this.failToStart = false});

  final bool failToStart;
  final List<SentryOptions> inits = [];

  @override
  void init(SentryOptions options) {
    if (failToStart) {
      throw StateError('does not start');
    }
    inits.add(options);
  }

  @override
  void addBreadcrumb(SentryJson breadcrumb) {}

  @override
  void captureException(ReportedError exception, SentryJson context) {}
}

/// A console that remembers what was written to it.
final class _RecordingSink implements ConsoleSink {
  final List<List<Object?>> warnings = [];

  @override
  void info(List<Object?> data) {}

  @override
  void warn(List<Object?> data) {
    warnings.add(data);
  }

  @override
  void error(List<Object?> data) {}
}

void main() {
  group('createMonitoring', () {
    for (final (name, dsn) in <(String, String?)>[
      ('absent', null),
      ('empty', ''),
      ('blank', '   '),
    ]) {
      test('is the console when the address is $name', () {
        final sdk = _RecordingSdk();

        expect(createMonitoring(dsn, sdk: sdk), isA<ConsoleMonitoring>());
        expect(sdk.inits, isEmpty);
      });
    }

    test('is Sentry when there is an address, started with that address and '
        'the scrubbing', () {
      final sdk = _RecordingSdk();

      final monitoring = createMonitoring('  $_dsn  ', sdk: sdk);

      expect(monitoring, isA<SentryMonitoring>());
      expect(sdk.inits, hasLength(1));
      expect(sdk.inits.single.dsn, equals(_dsn));
      expect(sdk.inits.single.sendDefaultPii, isFalse);
    });

    test('stays the console, and says why once, when the address is not a '
        'DSN', () {
      final sdk = _RecordingSdk();
      final sink = _RecordingSink();

      final monitoring = createMonitoring(
        'not an address',
        sdk: sdk,
        sink: sink,
      );

      expect(monitoring, isA<ConsoleMonitoring>());
      expect(sdk.inits, isEmpty);
      expect(sink.warnings, hasLength(1));
      expect(sink.warnings.single.join(' '), contains('invalidDsn'));
      expect(sink.warnings.single.join(' '), isNot(contains('not an address')));
    });

    test('stays the console when the SDK does not start', () {
      final sink = _RecordingSink();

      final monitoring = createMonitoring(
        _dsn,
        sdk: _RecordingSdk(failToStart: true),
        sink: sink,
      );

      expect(monitoring, isA<ConsoleMonitoring>());
      expect(sink.warnings.single.join(' '), contains('sdkFailed'));
    });

    test('stays the console when the build has no SDK to report with', () {
      final sink = _RecordingSink();

      final monitoring = createMonitoring(_dsn, sink: sink);

      expect(monitoring, isA<ConsoleMonitoring>());
      expect(sink.warnings.single.join(' '), contains(sentrySdkUnavailable));
      expect(
        sink.warnings.single.join(' '),
        contains(MonitoringEvent.monitoringNotStarted.value),
      );
    });
  });

  group('the container, given an address', () {
    ContainerRuntime runtimeWith({SentrySdk? sdk, Monitoring? monitoring}) =>
        ContainerRuntime(
          clock: FakeClock(),
          sleep: immediateSleep,
          fileStore: createFileStore(MemoryFileVolume()),
          fixtureFiles: readFixtureFiles(),
          sentrySdk: sdk,
          monitoring: monitoring,
        );

    DevConfiguration configuration({String? dsn}) =>
        DevConfiguration(sentryDsn: dsn, latency: aDuration(0));

    test('starts Sentry once, with that address', () async {
      final sdk = _RecordingSdk();

      final container = built(
        await createContainer(configuration(dsn: _dsn), runtimeWith(sdk: sdk)),
      );
      addTearDown(container.dispose);

      expect(sdk.inits, hasLength(1));
      expect(sdk.inits.single.dsn, equals(_dsn));
      expect(container.monitoring, isA<SentryMonitoring>());
    });

    test('starts nothing without an address', () async {
      final sdk = _RecordingSdk();

      final container = built(
        await createContainer(configuration(), runtimeWith(sdk: sdk)),
      );
      addTearDown(container.dispose);

      expect(sdk.inits, isEmpty);
      expect(container.monitoring, isA<ConsoleMonitoring>());
    });

    test(
      'keeps the monitoring the runtime hands over, address or not',
      () async {
        final sdk = _RecordingSdk();
        final handed = FakeMonitoring();

        final container = built(
          await createContainer(
            configuration(dsn: _dsn),
            runtimeWith(sdk: sdk, monitoring: handed),
          ),
        );
        addTearDown(container.dispose);

        expect(sdk.inits, isEmpty);
        expect(container.monitoring, same(handed));
      },
    );

    test('is started from the raw settings of the app', () async {
      final sdk = _RecordingSdk();

      final container = built(
        await startContainer(
          const RawSettings(adapters: 'dev', sentryDsn: '  $_dsn  '),
          runtimeWith(sdk: sdk),
          development: true,
        ),
      );
      addTearDown(container.dispose);

      expect(sdk.inits.single.dsn, equals(_dsn));
    });
  });
}
