import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/email_address.dart';
import 'package:test/test.dart';

import '../support/names.dart';

void main() {
  group('parseEmailAddress', () {
    test('trims and lower-cases a valid address', () {
      expect(
        parseEmailAddress('  Alice.Martin@Example.COM '),
        equals(ok('alice.martin@example.com')),
      );
    });

    for (final raw in ['a@b.co', 'first+tag@sub.example.org']) {
      test('accepts $raw', () {
        expect(parseEmailAddress(raw), equals(ok(raw)));
      });
    }

    for (final raw in ['', '   ']) {
      test('rejects the blank address ${formatJson(raw)} as required', () {
        expect(
          parseEmailAddress(raw),
          equals(
            err(
              validationError(ValidationField.email, ValidationRule.required),
            ),
          ),
        );
      });
    }

    for (final raw in [
      'alice',
      'alice@',
      '@example.com',
      'alice@example',
      'a b@example.com',
      'a@@b.com',
    ]) {
      test('rejects ${formatJson(raw)} as badly formed', () {
        expect(
          parseEmailAddress(raw),
          equals(
            err(
              validationError(
                ValidationField.email,
                ValidationRule.invalidFormat,
              ),
            ),
          ),
        );
      });
    }

    test('rejects an address longer than 254 characters', () {
      final tooLong = '${'a' * 250}@b.co';

      expect(
        parseEmailAddress(tooLong),
        equals(
          err(validationError(ValidationField.email, ValidationRule.tooLong)),
        ),
      );
    });
  });
}
