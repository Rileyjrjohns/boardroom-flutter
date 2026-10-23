import 'package:boardroom/features/auth/infrastructure/biometrics/device_biometric_gate.dart';
import 'package:test/test.dart';

// The values the gate and the platform layer exchange compare by what they
// hold, so that a test of the gate (or of the root) can say what the prompt
// was.

const AuthenticationPrompt _prompt = AuthenticationPrompt(
  promptMessage: 'Unlock',
  cancelLabel: 'Cancel',
  disableDeviceFallback: true,
  biometricsSecurityLevel: BiometricsSecurityLevel.strong,
);

void main() {
  group('PromptText', () {
    test('compares by its message and its cancel label', () {
      const text = PromptText(message: 'Unlock', cancelLabel: 'Cancel');

      expect(
        text,
        equals(const PromptText(message: 'Unlock', cancelLabel: 'Cancel')),
      );
      expect(
        text.hashCode,
        equals(
          const PromptText(message: 'Unlock', cancelLabel: 'Cancel').hashCode,
        ),
      );
      expect(
        text,
        isNot(
          equals(const PromptText(message: 'Other', cancelLabel: 'Cancel')),
        ),
      );
      expect(
        text,
        isNot(equals(const PromptText(message: 'Unlock', cancelLabel: 'No'))),
      );
    });

    test('prints what it says', () {
      expect(
        const PromptText(message: 'Unlock', cancelLabel: 'Cancel').toString(),
        equals('PromptText(Unlock, Cancel)'),
      );
    });
  });

  group('AuthenticationPrompt', () {
    test('compares by every field', () {
      expect(_prompt, equals(_prompt));
      expect(
        _prompt.hashCode,
        equals(
          const AuthenticationPrompt(
            promptMessage: 'Unlock',
            cancelLabel: 'Cancel',
            disableDeviceFallback: true,
            biometricsSecurityLevel: BiometricsSecurityLevel.strong,
          ).hashCode,
        ),
      );
      for (final other in [
        const AuthenticationPrompt(
          promptMessage: 'Other',
          cancelLabel: 'Cancel',
          disableDeviceFallback: true,
          biometricsSecurityLevel: BiometricsSecurityLevel.strong,
        ),
        const AuthenticationPrompt(
          promptMessage: 'Unlock',
          cancelLabel: 'No',
          disableDeviceFallback: true,
          biometricsSecurityLevel: BiometricsSecurityLevel.strong,
        ),
        const AuthenticationPrompt(
          promptMessage: 'Unlock',
          cancelLabel: 'Cancel',
          disableDeviceFallback: false,
          biometricsSecurityLevel: BiometricsSecurityLevel.strong,
        ),
        const AuthenticationPrompt(
          promptMessage: 'Unlock',
          cancelLabel: 'Cancel',
          disableDeviceFallback: true,
          biometricsSecurityLevel: BiometricsSecurityLevel.weak,
        ),
      ]) {
        expect(_prompt, isNot(equals(other)));
      }
    });

    test(
      'prints the level and the fallback, and not the text of the prompt',
      () {
        expect(
          _prompt.toString(),
          equals('AuthenticationPrompt(strong, disableDeviceFallback: true)'),
        );
      },
    );
  });

  group('LocalAuthenticationResult', () {
    test('compares by its success and its code', () {
      expect(
        const LocalAuthenticationResult.succeeded(),
        equals(const LocalAuthenticationResult(success: true)),
      );
      expect(
        const LocalAuthenticationResult.failed('lockout'),
        equals(
          const LocalAuthenticationResult(success: false, error: 'lockout'),
        ),
      );
      expect(
        const LocalAuthenticationResult.failed('lockout').hashCode,
        equals(const LocalAuthenticationResult.failed('lockout').hashCode),
      );
      expect(
        const LocalAuthenticationResult.failed('lockout'),
        isNot(equals(const LocalAuthenticationResult.failed('timeout'))),
      );
      expect(
        const LocalAuthenticationResult.failed(null),
        isNot(equals(const LocalAuthenticationResult.succeeded())),
      );
    });

    test('prints its success and its code', () {
      expect(
        const LocalAuthenticationResult.failed('lockout').toString(),
        equals('LocalAuthenticationResult(false, lockout)'),
      );
    });
  });
}
