import 'dart:async';

import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/constants.dart';
import 'package:boardroom/infrastructure/monitoring/console_monitoring.dart';
import 'package:test/test.dart';

typedef _Call = ({String method, List<Object?> data});

final class _RecordingSink implements ConsoleSink {
  final List<_Call> calls = [];

  @override
  void info(List<Object?> data) => calls.add((method: 'info', data: data));

  @override
  void warn(List<Object?> data) => calls.add((method: 'warn', data: data));

  @override
  void error(List<Object?> data) => calls.add((method: 'error', data: data));
}

final class _FailingSink implements ConsoleSink {
  @override
  void info(List<Object?> data) => throw StateError('console is gone');

  @override
  void warn(List<Object?> data) => throw StateError('console is gone');

  @override
  void error(List<Object?> data) => throw StateError('console is gone');
}

void main() {
  group('ConsoleMonitoring', () {
    test('writes an info event to the info channel, with its attributes', () {
      final sink = _RecordingSink();

      ConsoleMonitoring(sink).log(
        LogLevel.info,
        MonitoringEvent.voteSubmitted,
        {LogAttribute.meetingId: 'meeting-1'},
      );

      expect(sink.calls, hasLength(1));
      expect(sink.calls.single.method, equals('info'));
      expect(
        sink.calls.single.data,
        equals([
          logPrefix,
          MonitoringEvent.voteSubmitted.value,
          {'meetingId': 'meeting-1'},
        ]),
      );
    });

    test('writes a warning to the warn channel, '
        'and an event without attributes as an empty object', () {
      final sink = _RecordingSink();

      ConsoleMonitoring(sink)
          .log(LogLevel.warn, MonitoringEvent.cacheEntryDiscarded);

      expect(sink.calls, hasLength(1));
      expect(sink.calls.single.method, equals('warn'));
      expect(
        sink.calls.single.data,
        equals([
          logPrefix,
          MonitoringEvent.cacheEntryDiscarded.value,
          <String, Object>{},
        ]),
      );
    });

    for (final level in valuesOf(LogLevel.values)) {
      test(
        'writes a $level event to exactly one channel, never dropping it',
        () {
          final sink = _RecordingSink();

          ConsoleMonitoring(sink).log(
            LogLevel.values.firstWhere((candidate) => candidate.value == level),
            MonitoringEvent.voteQueued,
          );

          expect(sink.calls, hasLength(1));
        },
      );
    }

    test(
      'writes a captured error to the error channel, with its code and fields',
      () {
        final sink = _RecordingSink();
        final error = storageWriteFailed('disk full');

        ConsoleMonitoring(sink)
          ..captureError(MonitoringEvent.cacheWriteFailed, error, {
            LogAttribute.resource: 'meeting',
          })
          ..captureError(MonitoringEvent.cachePurgeFailed, error);

        expect(
          sink.calls.map((call) => call.method),
          equals(['error', 'error']),
        );
        expect(
          sink.calls.map((call) => call.data),
          equals([
            [
              logPrefix,
              MonitoringEvent.cacheWriteFailed.value,
              error,
              {'resource': 'meeting'},
            ],
            [
              logPrefix,
              MonitoringEvent.cachePurgeFailed.value,
              error,
              <String, Object>{},
            ],
          ]),
        );
      },
    );

    test('never throws, whatever the console does', () {
      final monitoring = ConsoleMonitoring(_FailingSink());

      expect(
        () => monitoring.log(LogLevel.info, MonitoringEvent.voteQueued),
        returnsNormally,
      );
      expect(
        () => monitoring.log(LogLevel.warn, MonitoringEvent.voteRejected),
        returnsNormally,
      );
      expect(
        () => monitoring.captureError(
          MonitoringEvent.voteEnqueueFailed,
          storageWriteFailed(),
        ),
        returnsNormally,
      );
    });

    test('writes to the global console by default', () {
      final printed = <String>[];

      runZoned(
        () => const ConsoleMonitoring().log(
          LogLevel.info,
          MonitoringEvent.voteQueued,
        ),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      expect(printed, equals(['info $logPrefix voteQueued {}']));
    });

    test('tells the channel apart in the lines it prints', () {
      final printed = <String>[];
      final error = storageWriteFailed();

      runZoned(
        () => const ConsoleMonitoring()
          ..log(LogLevel.info, MonitoringEvent.voteQueued)
          ..log(LogLevel.warn, MonitoringEvent.voteRejected)
          ..captureError(MonitoringEvent.voteEnqueueFailed, error),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      expect(
        printed.map((line) => line.split(' ').first),
        equals(['info', 'warn', 'error']),
      );
    });
  });
}
