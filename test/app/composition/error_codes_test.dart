import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:test/test.dart';

// The scenario of `errors.test.ts` in React Native about the codes of every
// family. The families are in the core and in the features, and the
// composition is the one place that sees all of them, so the scenario is here,
// with the same name (`tool/scenario_parity.dart` reads it for
// `errors.test.ts`: `splitScenarioFiles`).

void main() {
  group('error codes', () {
    final families = {
      'validation': valuesOf(ValidationErrorCode.values),
      'authentication': valuesOf(AuthenticationErrorCode.values),
      'repository': valuesOf(RepositoryErrorCode.values),
      'voting': valuesOf(VotingErrorCode.values),
      'voteDelivery': valuesOf(VoteDeliveryErrorCode.values),
      'biometric': valuesOf(BiometricErrorCode.values),
      'storage': valuesOf(StorageErrorCode.values),
      'screenProtection': valuesOf(ScreenProtectionErrorCode.values),
    };

    test('are unique across every family, '
        'so that a union of errors is told apart by code alone', () {
      final all = families.values.expand((codes) => codes).toList();

      expect(all.toSet().length, equals(all.length));
    });
  });
}
