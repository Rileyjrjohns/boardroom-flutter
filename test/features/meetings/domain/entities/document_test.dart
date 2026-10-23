// The arguments restate the values of the scenario, even when they are the
// defaults of the builders.
// ignore_for_file: avoid_redundant_argument_values

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/builders/names.dart';

DocumentInput _valid({
  String title = 'Financial statements',
  num pageCount = 12,
}) => DocumentInput(
  id: aDocumentId(),
  title: title,
  confidentiality: ConfidentialityLevel.internal,
  pageCount: pageCount,
);

void main() {
  group('createDocument', () {
    test('builds a document with a trimmed title', () {
      expect(
        createDocument(_valid(title: '  Financial statements ')),
        equals(
          ok(
            Document(
              id: aDocumentId(),
              title: 'Financial statements',
              confidentiality: ConfidentialityLevel.internal,
              pageCount: 12,
            ),
          ),
        ),
      );
    });

    test('rejects a blank title', () {
      expect(
        createDocument(_valid(title: '')),
        equals(
          err(validationError(ValidationField.title, ValidationRule.required)),
        ),
      );
    });

    for (final (pageCount, rule) in <(num, ValidationRule)>[
      (0, ValidationRule.outOfRange),
      (10001, ValidationRule.outOfRange),
      (1.5, ValidationRule.notAnInteger),
    ]) {
      test('rejects the page count ${formatPretty(pageCount)}', () {
        expect(
          createDocument(_valid(pageCount: pageCount)),
          equals(err(validationError(ValidationField.pageCount, rule))),
        );
      });
    }
  });

  group('isConfidential', () {
    test('is true for a confidential document only', () {
      expect(isConfidential(aConfidentialDocument()), isTrue);
      expect(
        isConfidential(
          aDocument(confidentiality: ConfidentialityLevel.internal),
        ),
        isFalse,
      );
      expect(
        isConfidential(aDocument(confidentiality: ConfidentialityLevel.public)),
        isFalse,
      );
    });
  });

  group('parseConfidentialityLevel', () {
    for (final level in ConfidentialityLevel.values) {
      test('parses ${level.value}', () {
        expect(parseConfidentialityLevel(level.value), equals(ok(level)));
      });
    }

    test('rejects an unknown level', () {
      expect(
        parseConfidentialityLevel('secret'),
        equals(
          err(
            validationError(
              ValidationField.confidentialityLevel,
              ValidationRule.unknownValue,
            ),
          ),
        ),
      );
    });
  });
}
