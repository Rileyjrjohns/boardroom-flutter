import 'package:boardroom/core/application/retryable_codes.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:test/test.dart';

void main() {
  group('the codes of the core a second try can fix', () {
    test('are the network, a fault of the server and a store that could not '
        'be read', () {
      expect(
        [...coreRetryableCodes]..sort(),
        equals(
          [
            RepositoryErrorCode.networkUnavailable.value,
            RepositoryErrorCode.unexpected.value,
            StorageErrorCode.readFailed.value,
          ]..sort(),
        ),
      );
    });

    for (final code in [
      RepositoryErrorCode.unauthorized.value,
      RepositoryErrorCode.forbidden.value,
      RepositoryErrorCode.notFound.value,
      StorageErrorCode.writeFailed.value,
      ValidationErrorCode.validation.value,
    ]) {
      test('leave out $code: asking again cannot change it', () {
        expect(coreRetryableCodes.contains(code), isFalse);
      });
    }
  });
}
