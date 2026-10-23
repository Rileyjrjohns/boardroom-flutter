import 'package:boardroom/core/domain/policies/cache_age.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';

void main() {
  final maxAge = aDuration(60000);

  group('isWithinMaxAge', () {
    test('accepts an entry that was just stored', () {
      expect(isWithinMaxAge(now, now, maxAge), isTrue);
    });

    test('accepts an entry younger than the maximum age, '
        'and one of exactly that age', () {
      expect(isWithinMaxAge(at(-59999), now, maxAge), isTrue);
      expect(isWithinMaxAge(at(-60000), now, maxAge), isTrue);
    });

    test(
      'refuses an entry older than the maximum age, by one millisecond already',
      () {
        expect(isWithinMaxAge(at(-60001), now, maxAge), isFalse);
      },
    );

    test(
      'refuses an entry dated in the future, by one millisecond already',
      () {
        expect(isWithinMaxAge(at(1), now, maxAge), isFalse);
        expect(isWithinMaxAge(at(3600000), now, maxAge), isFalse);
      },
    );

    test('with a maximum age of zero, '
        'only an entry stored at this very instant is accepted', () {
      expect(isWithinMaxAge(now, now, aDuration(0)), isTrue);
      expect(isWithinMaxAge(at(-1), now, aDuration(0)), isFalse);
    });
  });
}
