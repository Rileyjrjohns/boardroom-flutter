import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/shared/validation.dart';
import 'package:test/test.dart';

import '../support/names.dart';

const ValidationField field = ValidationField.title;

void main() {
  group('requireText', () {
    test('returns the trimmed text', () {
      expect(requireText(field, '  Budget  ', 10), equals(ok('Budget')));
    });

    for (final raw in ['', '   ', '\n\t']) {
      test('rejects the blank text ${formatJson(raw)}', () {
        expect(
          requireText(field, raw, 10),
          equals(err(validationError(field, ValidationRule.required))),
        );
      });
    }

    test(
      'accepts a text of exactly the maximum length and rejects a longer one',
      () {
        expect(requireText(field, 'a' * 10, 10), equals(ok('a' * 10)));
        expect(
          requireText(field, 'a' * 11, 10),
          equals(err(validationError(field, ValidationRule.tooLong))),
        );
      },
    );

    test('measures the length after trimming', () {
      expect(requireText(field, '  ${'a' * 10}  ', 10), equals(ok('a' * 10)));
    });
  });

  group('optionalText', () {
    for (final raw in <String?>[null, '', '   ']) {
      test('treats ${formatJson(raw)} as no text', () {
        expect(optionalText(field, raw, 10), equals(ok<String?>(null)));
      });
    }

    test('validates a text that is present', () {
      expect(optionalText(field, ' Notes ', 10), equals(ok('Notes')));
      expect(
        optionalText(field, 'a' * 11, 10),
        equals(err(validationError(field, ValidationRule.tooLong))),
      );
    });
  });

  group('requireIntegerInRange', () {
    test('accepts the bounds and what lies between', () {
      expect(requireIntegerInRange(field, 1, 1, 5), equals(ok(1)));
      expect(requireIntegerInRange(field, 5, 1, 5), equals(ok(5)));
    });

    for (final value in <num>[0.5, double.nan, double.infinity]) {
      test('rejects ${formatPretty(value)} as not an integer', () {
        expect(
          requireIntegerInRange(field, value, 1, 5),
          equals(err(validationError(field, ValidationRule.notAnInteger))),
        );
      });
    }

    for (final value in <num>[0, 6, -1]) {
      test('rejects ${formatPretty(value)} as out of range', () {
        expect(
          requireIntegerInRange(field, value, 1, 5),
          equals(err(validationError(field, ValidationRule.outOfRange))),
        );
      });
    }
  });

  group('hasDuplicates', () {
    test('detects a repeated key', () {
      expect(hasDuplicates(<Object>['a', 'b', 'a']), isTrue);
      expect(hasDuplicates(<Object>[1, 2, 1]), isTrue);
    });

    test('accepts distinct keys and an empty list', () {
      expect(hasDuplicates(<Object>['a', 'b']), isFalse);
      expect(hasDuplicates(<Object>[]), isFalse);
    });
  });

  group('isWellFormedText', () {
    for (final text in [
      '',
      'abc',
      'café',
      'café',
      '\u{1F600}',
      'a\u{1F600}b',
      '😀',
    ]) {
      test('accepts ${formatJson(text)}', () {
        expect(isWellFormedText(text), isTrue);
      });
    }

    for (final text in [
      '\ud800',
      '\udbff',
      '\udc00',
      '\udfff',
      'a\ud800',
      '\ud800a',
      '\udc00\ud800',
      '\ud800𐀀',
      '😀\ud83d',
    ]) {
      test('rejects ${formatJson(text)}', () {
        expect(isWellFormedText(text), isFalse);
      });
    }
  });
}
