import 'package:boardroom/infrastructure/shared/subscribers.dart';
import 'package:test/test.dart';

void main() {
  group('createSubscribers', () {
    test(
      'calls every listener with the value, in the order they subscribed',
      () {
        final subscribers = createSubscribers<int>((_) {});
        final calls = <String>[];
        subscribers
          ..subscribe((value) => calls.add('a$value'))
          ..subscribe((value) => calls.add('b$value'))
          ..notify(1);

        expect(calls, equals(['a1', 'b1']));
      },
    );

    test(
      'makes a subscription of its own each time, even for the same function',
      () {
        final subscribers = createSubscribers<int>((_) {});
        final calls = <int>[];
        void listener(int value) => calls.add(value);
        final stopFirst = subscribers.subscribe(listener);
        subscribers
          ..subscribe(listener)
          ..notify(1);
        stopFirst();
        subscribers.notify(2);

        expect(calls, equals([1, 1, 2]));
        expect(subscribers.size, equals(1));
      },
    );

    test(
      'removes a subscription once: removing it again leaves the others',
      () {
        final subscribers = createSubscribers<int>((_) {});
        var kept = 0;
        final stop = subscribers.subscribe((_) {});
        subscribers.subscribe((_) => kept += 1);

        stop();
        stop();
        subscribers.notify(1);

        expect(kept, equals(1));
        expect(subscribers.size, equals(1));
      },
    );

    test('reports a listener that throws, calls the ones after it, '
        'and does not throw', () {
      final errors = <Object>[];
      final subscribers = createSubscribers<int>(errors.add);
      final received = <int>[];
      final failure = StateError('broken listener');
      subscribers
        ..subscribe((_) => throw failure)
        ..subscribe(received.add);

      expect(() => subscribers.notify(1), returnsNormally);

      expect(received, equals([1]));
      expect(errors, equals([failure]));
    });

    test('applies a subscription made while it notifies to the next value', () {
      final subscribers = createSubscribers<int>((_) {});
      final late = <int>[];
      subscribers.subscribe((_) {
        subscribers.subscribe(late.add);
      });

      subscribers.notify(1);
      expect(late, isEmpty);
      subscribers.notify(2);

      expect(late, equals([2]));
    });
  });
}
