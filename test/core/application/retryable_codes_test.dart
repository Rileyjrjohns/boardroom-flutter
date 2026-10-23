import 'package:boardroom/core/application/retryable_codes.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/features/auth/application/session/session_policy.dart';
import 'package:test/test.dart';

final List<String> _retryable = [
  RepositoryErrorCode.networkUnavailable.value,
  RepositoryErrorCode.unexpected.value,
  StorageErrorCode.readFailed.value,
  ScreenProtectionErrorCode.failed.value,
];
final List<String> _notRetryable = [
  RepositoryErrorCode.unauthorized.value,
  RepositoryErrorCode.forbidden.value,
  RepositoryErrorCode.notFound.value,
  StorageErrorCode.writeFailed.value,
  ValidationErrorCode.validation.value,
  AuthenticationErrorCode.notAuthenticated.value,
  AuthenticationErrorCode.sessionExpired.value,
  AuthenticationErrorCode.appLocked.value,
  AuthenticationErrorCode.sessionChanged.value,
  AuthenticationErrorCode.invalidCredentials.value,
  ScreenProtectionErrorCode.unsupported.value,
];

void main() {
  group('the codes a second try can fix', () {
    test('are these four, and no other', () {
      expect(([...retryableCodes]..sort()), equals([..._retryable]..sort()));
    });

    for (final code in _retryable) {
      test('includes $code', () {
        expect(isRetryableCode(code), isTrue);
      });
    }

    for (final code in _notRetryable) {
      test('leaves out $code: asking again cannot change it', () {
        expect(isRetryableCode(code), isFalse);
      });
    }

    test('offers a retry for a screen protection that failed, and not for a '
        'platform that has none', () {
      expect(isRetryableCode(ScreenProtectionErrorCode.failed.value), isTrue);
      expect(
        isRetryableCode(ScreenProtectionErrorCode.unsupported.value),
        isFalse,
      );
    });

    test('leaves out a code that is not one of the app, and an empty one', () {
      expect(isRetryableCode('unheardOf'), isFalse);
      expect(isRetryableCode(''), isFalse);
    });

    for (final code in [...sessionEndingCodes]) {
      test('leaves out $code: a failure that ends the session is final', () {
        expect(isRetryableCode(code), isFalse);
      });
    }
  });
}
