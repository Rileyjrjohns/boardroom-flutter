import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/features/auth/application/session/session_policy.dart';
import 'package:test/test.dart';

final List<String> _sessionEnding = [
  RepositoryErrorCode.unauthorized.value,
  AuthenticationErrorCode.notAuthenticated.value,
  AuthenticationErrorCode.sessionExpired.value,
  AuthenticationErrorCode.sessionChanged.value,
  AuthenticationErrorCode.appLocked.value,
];
final List<String> _others = [
  RepositoryErrorCode.networkUnavailable.value,
  RepositoryErrorCode.forbidden.value,
  RepositoryErrorCode.notFound.value,
  RepositoryErrorCode.unexpected.value,
  StorageErrorCode.readFailed.value,
  StorageErrorCode.writeFailed.value,
  ValidationErrorCode.validation.value,
  AuthenticationErrorCode.invalidCredentials.value,
  ScreenProtectionErrorCode.failed.value,
  ScreenProtectionErrorCode.unsupported.value,
];

void main() {
  group('the codes that end the session', () {
    test('are these five, and no other', () {
      expect(
        ([...sessionEndingCodes]..sort()),
        equals([..._sessionEnding]..sort()),
      );
    });

    for (final code in _sessionEnding) {
      test('recognises $code', () {
        expect(isSessionEndingCode(code), isTrue);
      });
    }

    for (final code in _others) {
      test(
        'does not recognise $code: it concerns one request, not the session',
        () {
          expect(isSessionEndingCode(code), isFalse);
        },
      );
    }

    test(
      'does not recognise a code that is not one of the app, nor an empty one',
      () {
        expect(isSessionEndingCode('anything'), isFalse);
        expect(isSessionEndingCode(''), isFalse);
      },
    );
  });

  group('the interval of the session check', () {
    test('is thirty seconds', () {
      expect(sessionCheckIntervalMillis, equals(30000));
    });
  });
}
