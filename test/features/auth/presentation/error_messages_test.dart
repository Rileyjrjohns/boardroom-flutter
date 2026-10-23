import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:boardroom/features/auth/presentation/error_messages.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/presentation/test_app.dart';

// The maps from a code to a text are exhaustive over their families and tell
// every code in both languages.

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final l10n = l10nOf(locale);

    group('in ${locale.languageCode}', () {
      test('tells every failure of the session', () {
        for (final code in AuthenticationErrorCode.values) {
          expect(sessionErrorMessages, contains(code.value));
          expect(sessionErrorMessages[code.value]!(l10n), isNotEmpty);
        }
      });

      test(
        'tells every outcome of the biometric prompt on the lock screen',
        () {
          for (final code in BiometricErrorCode.values) {
            expect(unlockErrorMessages, contains(code.value));
            expect(unlockErrorMessage(l10n, code.value), isNotEmpty);
          }
          expect(
            unlockErrorMessage(l10n, 'somethingNew'),
            unlockErrorMessage(l10n, 'unexpected'),
          );
        },
      );

      test('tells every failure of a sign-in', () {
        for (final code in [
          ValidationErrorCode.validation.value,
          AuthenticationErrorCode.invalidCredentials.value,
          RepositoryErrorCode.networkUnavailable.value,
          RepositoryErrorCode.unexpected.value,
          StorageErrorCode.writeFailed.value,
        ]) {
          expect(signInErrorMessages, contains(code));
          expect(signInErrorMessage(l10n, code), isNotEmpty);
        }
        expect(
          signInErrorMessage(l10n, 'somethingNew'),
          signInErrorMessage(l10n, 'unexpected'),
        );
      });

      test('tells the email by the rule it broke, and the password always '
          'the same', () {
        expect(
          emailRuleMessage(l10n, ValidationRule.required),
          l10n.authSignInEmailRequired,
        );
        expect(
          emailRuleMessage(l10n, ValidationRule.tooLong),
          l10n.authSignInEmailTooLong,
        );
        for (final rule in ValidationRule.values) {
          expect(emailRuleMessage(l10n, rule), isNotEmpty);
        }
        expect(passwordRuleMessage(l10n), l10n.authSignInPasswordRequired);
      });

      test('asks for the biometric proof in words', () {
        expect(
          biometricPromptMessage(l10n, BiometricReason.unlockApp),
          l10n.authBiometricUnlockApp,
        );
        expect(
          biometricPromptMessage(l10n, BiometricReason.confirmVote),
          l10n.authBiometricConfirmVote,
        );
      });
    });
  }
}
