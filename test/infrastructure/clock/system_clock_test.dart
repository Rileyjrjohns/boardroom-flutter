import 'package:boardroom/infrastructure/clock/system_clock.dart';
import 'package:test/test.dart';

void main() {
  group('SystemClock', () {
    test('reads the time of the device through the function it is given', () {
      const clock = SystemClock(_fixedReading);

      expect(clock.now(), equals(1900000000123));
    });

    test('reads the real clock by default', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final reading = const SystemClock().now();
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(reading, greaterThanOrEqualTo(before));
      expect(reading, lessThanOrEqualTo(after));
    });

    test('follows the clock as it moves', () {
      num millis = 1000;
      final clock = SystemClock(() => millis);

      expect(clock.now(), equals(1000));
      millis = 2500;
      expect(clock.now(), equals(2500));
    });

    for (final (name, reading, expected) in <(String, num, int)>[
      ('a fractional reading', 1500.9, 1500),
      ('a reading before 1970', -5000, 0),
      ('a reading that is not a number', double.nan, 0),
      ('an infinite reading', double.infinity, 0),
      ('a reading beyond the range of an instant', 9000000000000000, 0),
    ]) {
      test('never fails on $name', () {
        expect(SystemClock(() => reading).now(), equals(expected));
      });
    }
  });
}

num _fixedReading() => 1900000000123;
