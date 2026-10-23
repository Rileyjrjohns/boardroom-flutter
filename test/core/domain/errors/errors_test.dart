import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:test/test.dart';

import '../../../support/builders/matchers.dart';

void main() {
  group('error factories', () {
    test('build a validation error with its field and rule', () {
      expect(
        validationError(ValidationField.email, ValidationRule.required),
        isAppError(ValidationErrorCode.validation.value, {
          'field': ValidationField.email,
          'rule': ValidationRule.required,
        }),
      );
    });

    test('build the repository errors', () {
      expect(
        networkUnavailable().code,
        equals(RepositoryErrorCode.networkUnavailable.value),
      );
      expect(notFound().code, equals(RepositoryErrorCode.notFound.value));
      expect(
        unauthorized().code,
        equals(RepositoryErrorCode.unauthorized.value),
      );
      expect(forbidden(), isAppError(RepositoryErrorCode.forbidden.value));
    });

    test('carry a technical cause only when one is given', () {
      expect(unexpected(), isAppError(RepositoryErrorCode.unexpected.value));
      expect(
        unexpected('HTTP 500'),
        isAppError(RepositoryErrorCode.unexpected.value, {'cause': 'HTTP 500'}),
      );
      expect(
        storageReadFailed(),
        isAppError(StorageErrorCode.readFailed.value),
      );
      expect(
        storageReadFailed('disk'),
        isAppError(StorageErrorCode.readFailed.value, {'cause': 'disk'}),
      );
      expect(
        storageWriteFailed(),
        isAppError(StorageErrorCode.writeFailed.value),
      );
      expect(
        storageWriteFailed('full'),
        isAppError(StorageErrorCode.writeFailed.value, {'cause': 'full'}),
      );
    });
  });
}
