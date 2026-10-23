import 'dart:async';

import 'package:boardroom/core/infrastructure/shared/serial_queue.dart';
import 'package:test/test.dart';

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  group('createSerialQueue', () {
    test('runs the jobs one at a time, in the order they were asked for, '
        'whatever the order they settle in', () async {
      final queue = createSerialQueue();
      final log = <String>[];
      final first = Completer<String>();
      final second = Completer<String>();

      final a = queue(() async {
        log.add('start a');
        final value = await first.future;
        log.add('end a');
        return value;
      });
      final b = queue(() async {
        log.add('start b');
        final value = await second.future;
        log.add('end b');
        return value;
      });
      second.complete('b');
      await _turn();
      expect(log, equals(['start a']));
      first.complete('a');

      expect(await Future.wait([a, b]), equals(['a', 'b']));
      expect(log, equals(['start a', 'end a', 'start b', 'end b']));
    });

    test('gives each caller what its own job gave', () async {
      final queue = createSerialQueue();

      final one = queue(() async => 1);
      final other = queue(() async => 'x');

      expect(await one, equals(1));
      expect(await other, equals('x'));
    });

    test('keeps going after a job fails, '
        'and gives the failure to the caller of that job only', () async {
      final queue = createSerialQueue();
      final failing = queue<int>(() => Future.error(StateError('a failure')));
      final after = queue(() async => 'still running');

      await expectLater(failing, throwsA(isA<StateError>()));
      expect(await after, equals('still running'));
    });

    test(
      'keeps going after a job throws before it returns a promise',
      () async {
        final queue = createSerialQueue();
        final throwing = queue<int>(() => throw StateError('synchronous'));
        final after = queue(() async => 2);

        await expectLater(throwing, throwsA(isA<StateError>()));
        expect(await after, equals(2));
      },
    );

    test('keeps one queue apart from another', () async {
      final one = createSerialQueue();
      final other = createSerialQueue();
      final blocked = Completer<int>();
      unawaited(one(() => blocked.future));

      expect(await other(() async => 'free'), equals('free'));
      blocked.complete(0);
    });
  });
}
