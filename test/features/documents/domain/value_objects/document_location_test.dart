import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:test/test.dart';

void main() {
  group('parseDocumentLocation', () {
    test('keeps an opaque reference, trimmed', () {
      expect(
        parseDocumentLocation(' file:///private/doc-1.pdf '),
        equals(ok('file:///private/doc-1.pdf')),
      );
    });

    test('rejects a blank reference', () {
      expect(
        parseDocumentLocation('  '),
        equals(
          err(
            validationError(
              ValidationField.documentLocation,
              ValidationRule.required,
            ),
          ),
        ),
      );
    });

    test('rejects a reference longer than 2048 characters', () {
      expect(
        parseDocumentLocation('a' * 2049),
        equals(
          err(
            validationError(
              ValidationField.documentLocation,
              ValidationRule.tooLong,
            ),
          ),
        ),
      );
    });
  });
}
