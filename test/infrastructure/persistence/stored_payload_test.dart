import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/infrastructure/persistence/stored_document.dart';
import 'package:boardroom/infrastructure/persistence/stored_payload.dart';
import 'package:test/test.dart';

import '../../domain/support/builders.dart';

// What the caches share when a row is read back. React Native has no test file
// for it (it is inside the schema of each cache, tested through the caches).

Result<int, ValidationError> _pageCountOf(StoredDocument stored) =>
    stored.pageCount == 3
    ? ok(3)
    : err(
        validationError(ValidationField.pageCount, ValidationRule.outOfRange),
      );

void main() {
  final document = [
    '{"id":"document-1","title":"Financial statements",',
    '"confidentiality":"internal","pageCount":3}',
  ].join();

  group('decodePayload', () {
    test('gives what the domain makes of a payload that passes', () {
      expect(
        decodePayload(document, StoredDocument.fromJson, _pageCountOf),
        equals(ok(3)),
      );
    });

    test('says nothing of the place of the flaw in text that is not JSON', () {
      expect(
        decodePayload('not json', StoredDocument.fromJson, _pageCountOf),
        equals(err(const Unreadable())),
      );
    });

    test('says where the shape of the JSON is wrong, never what it held', () {
      expect(
        decodePayload(
          '{"id":"document-1","title":"A secret"}',
          StoredDocument.fromJson,
          _pageCountOf,
        ),
        equals(err(const Unreadable('confidentiality'))),
      );
    });

    test('says the payload as a whole is wrong when it is no object', () {
      expect(
        decodePayload('3', StoredDocument.fromJson, _pageCountOf),
        equals(err(const Unreadable(r'$'))),
      );
    });

    test('says nothing of the place when the values are refused '
        'by the domain', () {
      expect(
        decodePayload(
          document.replaceFirst('"pageCount":3', '"pageCount":4'),
          StoredDocument.fromJson,
          _pageCountOf,
        ),
        equals(err(const Unreadable())),
      );
    });
  });

  group('instantOf', () {
    test('is the instant a number stands for', () {
      expect(instantOf(0), equals(at(-now)));
      expect(instantOf(now), equals(now));
    });

    test('is nothing for what is not an instant', () {
      for (final column in [null, 'text', -5, 1.5, double.nan, true]) {
        expect(instantOf(column), isNull, reason: '$column');
      }
    });
  });

  group('Unreadable', () {
    test('compares by the places it reports', () {
      expect(const Unreadable('a'), equals(const Unreadable('a')));
      expect(const Unreadable('a').hashCode, const Unreadable('a').hashCode);
      expect(const Unreadable('a'), isNot(equals(const Unreadable('b'))));
      expect('${const Unreadable('a')}', equals('Unreadable(a)'));
    });
  });
}
