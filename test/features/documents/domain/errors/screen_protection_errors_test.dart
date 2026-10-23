import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:test/test.dart';

// The scenario of `errors.test.ts` in React Native that is about the errors of
// `documents`. In Dart the family is in its feature, so its scenario is here,
// with the same name (`tool/scenario_parity.dart` reads it for
// `errors.test.ts`: `splitScenarioFiles`).

void main() {
  group('error factories', () {
    test('build the screen protection errors', () {
      expect([
        screenProtectionUnsupported().code,
        screenProtectionFailed().code,
      ], equals(valuesOf(ScreenProtectionErrorCode.values)));
    });
  });
}
