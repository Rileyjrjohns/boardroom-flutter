import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:test/test.dart';

import '../../../../support/builders/matchers.dart';

// The scenarios of `errors.test.ts` in React Native that are about the errors
// of `auth`. In Dart the families are in their feature, so their scenarios are
// here, with the same names (`tool/scenario_parity.dart` reads them for
// `errors.test.ts`: `splitScenarioFiles`).

void main() {
  group('error factories', () {
    test('build the authentication errors', () {
      expect(
        invalidCredentials().code,
        equals(AuthenticationErrorCode.invalidCredentials.value),
      );
      expect(
        sessionExpired().code,
        equals(AuthenticationErrorCode.sessionExpired.value),
      );
      expect(
        notAuthenticated().code,
        equals(AuthenticationErrorCode.notAuthenticated.value),
      );
      expect(
        sessionChanged().code,
        equals(AuthenticationErrorCode.sessionChanged.value),
      );
      expect(appLocked(), isAppError(AuthenticationErrorCode.appLocked.value));
    });

    test('build the biometric errors', () {
      expect([
        biometricUnavailable().code,
        biometricNotEnrolled().code,
        biometricCancelled().code,
        biometricFailed().code,
        biometricLockedOut().code,
      ], equals(valuesOf(BiometricErrorCode.values)));
    });
  });
}
