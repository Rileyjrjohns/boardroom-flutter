import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/infrastructure/http/dto/wire.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import '../../../domain/support/names.dart';

bool _reads(Object text) {
  try {
    readInstantMillis(text);
    return true;
  } on FormatException {
    return false;
  }
}

void main() {
  group('isoInstantSchema', () {
    for (final (text, millis) in [
      ('2030-03-17T17:46:40.000Z', 1900000000000),
      ('2030-03-17T17:46:40Z', 1900000000000),
      ('2030-03-17T17:46:40.5Z', 1900000000500),
      ('2030-03-17T17:46:40.123456789Z', 1900000000123),
      ('2030-03-17T18:46:40+01:00', 1900000000000),
      ('2030-03-17T12:46:40-05:00', 1900000000000),
      ('1970-01-01T00:00:00.000Z', 0),
      ('+275760-09-13T00:00:00.000Z', 8640000000000000),
    ]) {
      test('reads $text as $millis', () {
        expect(readInstantMillis(text), equals(millis));
      });
    }

    for (final text in [
      '2030-03-17',
      '2030-03-17T17:46:40',
      '2030-03-17 17:46:40Z',
      '17/03/2030',
      '1900000000000',
      'yesterday',
      '',
      '2030-13-17T17:46:40Z',
      '2030-03-32T17:46:40Z',
      '2030-03-17T25:46:40Z',
      ' 2030-03-17T17:46:40Z',
    ]) {
      test('refuses ${formatJson(text)}', () {
        expect(_reads(text), isFalse);
      });
    }

    for (final millis in [1900000000000, 0, 8640000000000000, 1900000000123]) {
      test('reads back what toIsoString wrote for $millis', () {
        final instant = unwrap(parseInstant(millis));

        expect(readInstantMillis(toIsoString(instant)), equals(millis));
      });
    }

    test('refuses a number: instants are strings on the wire', () {
      expect(_reads(1900000000000), isFalse);
    });
  });

  group('the instants of the wire, in Dart', () {
    test('writes the instant of the tests as the API does', () {
      expect(toIsoString(now), equals('2030-03-17T17:46:40.000Z'));
    });

    test('refuses a day the month does not have, and accepts the '
        '29th of February of a leap year', () {
      expect(_reads('2030-02-29T00:00:00Z'), isFalse);
      expect(_reads('2028-02-29T00:00:00Z'), isTrue);
      expect(_reads('2030-04-31T00:00:00Z'), isFalse);
    });

    test('refuses an hour, a minute, a second or an offset out of range', () {
      expect(_reads('2030-03-17T24:00:00Z'), isTrue);
      expect(_reads('2030-03-17T24:00:01Z'), isFalse);
      expect(_reads('2030-03-17T10:60:00Z'), isFalse);
      expect(_reads('2030-03-17T10:00:60Z'), isFalse);
      expect(_reads('2030-03-17T10:00:00+24:00'), isFalse);
      expect(_reads('2030-03-17T10:00:00+01:60'), isFalse);
    });

    test(
      'refuses a time beyond the range of a date, and the year minus zero',
      () {
        expect(_reads('+275760-09-13T00:00:00.001Z'), isFalse);
        expect(_reads('-000000-01-01T00:00:00Z'), isFalse);
        expect(readInstantMillis('-000001-01-01T00:00:00.000Z'), isNegative);
      },
    );

    test('writes a year outside 0000-9999 with a sign and six '
        'digits, as toISOString does', () {
      expect(
        writeInstantMillis(8640000000000000),
        equals('+275760-09-13T00:00:00.000Z'),
      );
      expect(
        writeInstantMillis(readInstantMillis('-000001-01-01T00:00:00.000Z')),
        equals('-000001-01-01T00:00:00.000Z'),
      );
      expect(writeInstantMillis(-1), equals('1969-12-31T23:59:59.999Z'));
    });

    test('lets a missing optional instant be absent when written', () {
      expect(writeOptionalInstantMillis(null), isNull);
      expect(writeOptionalInstantMillis(0), equals('1970-01-01T00:00:00.000Z'));
    });
  });

  group('decodeWire, in Dart', () {
    test(r'says $ for a body that is not an object', () {
      for (final body in <Object?>[null, 'text', 12, <Object?>[]]) {
        expect(
          decodeWire<Object>(body, (json) => json),
          equals(err(const WireFailure(r'$'))),
        );
      }
    });

    test(r'says $ for a reader that fails in a way the generated code does not '
        'wrap', () {
      expect(
        decodeWire<Object>(
          <String, Object?>{},
          (json) => throw StateError('x'),
        ),
        equals(err(const WireFailure(r'$'))),
      );
    });
  });
}
