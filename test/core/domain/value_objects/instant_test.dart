import 'dart:convert';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/builders/names.dart';

const int _maxDateMillis = 8640000000000000;

Instant instant(int epochMillis) => unwrap(parseInstant(epochMillis));

void main() {
  group('parseInstant', () {
    test('accepts whole milliseconds since the epoch, bounds included', () {
      expect(parseInstant(0), equals(ok(0)));
      expect(parseInstant(1900000000000), equals(ok(1900000000000)));
      expect(parseInstant(_maxDateMillis), equals(ok(_maxDateMillis)));
    });

    for (final value in <num>[1.5, double.nan, double.infinity]) {
      test('rejects ${formatPretty(value)} as not an integer', () {
        expect(
          parseInstant(value),
          equals(
            err(
              validationError(
                ValidationField.instant,
                ValidationRule.notAnInteger,
              ),
            ),
          ),
        );
      });
    }

    for (final value in [-1, _maxDateMillis + 1]) {
      test('rejects ${formatPretty(value)} as out of range', () {
        expect(
          parseInstant(value),
          equals(
            err(
              validationError(
                ValidationField.instant,
                ValidationRule.outOfRange,
              ),
            ),
          ),
        );
      });
    }

    test('gives an instant that is always a valid Date', () {
      final date = DateTime.fromMillisecondsSinceEpoch(
        instant(_maxDateMillis),
        isUtc: true,
      );

      expect(date.millisecondsSinceEpoch, equals(_maxDateMillis));
    });

    test('serialises as a plain number', () {
      expect(jsonEncode({'at': instant(1000)}), equals('{"at":1000}'));
    });
  });

  group('comparison', () {
    final earlier = instant(1000);
    final later = instant(2000);

    test('orders two instants', () {
      expect(isBefore(earlier, later), isTrue);
      expect(isBefore(later, earlier), isFalse);
    });

    test(
      'treats the same instant as neither before nor after, but as at-or-after',
      () {
        expect(isBefore(earlier, earlier), isFalse);
        expect(isAtOrAfter(earlier, earlier), isTrue);
        expect(isAtOrAfter(later, earlier), isTrue);
        expect(isAtOrAfter(earlier, later), isFalse);
      },
    );
  });

  group('plus', () {
    test('shifts an instant forward by a duration', () {
      expect(plus(instant(1000), aDuration(500)), equals(ok(1500)));
      expect(plus(instant(1000), aDuration(0)), equals(ok(1000)));
    });

    test('fails when the result leaves the supported range', () {
      expect(
        plus(instant(_maxDateMillis), aDuration(1)),
        equals(
          err(
            validationError(ValidationField.instant, ValidationRule.outOfRange),
          ),
        ),
      );
    });
  });

  group('millisBetween', () {
    test('is signed', () {
      expect(millisBetween(instant(1000), instant(3500)), equals(2500));
      expect(millisBetween(instant(3500), instant(1000)), equals(-2500));
      expect(millisBetween(instant(1000), instant(1000)), equals(0));
    });
  });
}
