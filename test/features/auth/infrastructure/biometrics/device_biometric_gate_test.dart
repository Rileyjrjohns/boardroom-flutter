import 'dart:async';

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/infrastructure/biometrics/device_biometric_gate.dart';
import 'package:test/test.dart';

import '../../../../support/fakes/fake_monitoring.dart';

// What the platform does when it is asked a question about the capability:
// answers, throws, or never answers.
const Object _never = Object();

/// A platform whose answers the test sets, and that remembers what it was
/// asked.
final class _ScriptedPlatform implements LocalAuthenticationApi {
  Object hardware = true;
  Object enrolled = true;
  Object outcome = const LocalAuthenticationResult.succeeded();
  int enrolmentQuestions = 0;
  final List<AuthenticationPrompt> prompts = [];

  @override
  Future<bool> hasHardware() => _answer(hardware);

  @override
  Future<bool> isEnrolled() {
    enrolmentQuestions += 1;
    return _answer(enrolled);
  }

  @override
  Future<LocalAuthenticationResult> authenticate(
    AuthenticationPrompt prompt,
  ) async {
    prompts.add(prompt);
    return switch (outcome) {
      final Exception failure => throw failure,
      final LocalAuthenticationResult result => result,
      _ => throw StateError('A scripted outcome is a result or a failure.'),
    };
  }
}

Future<bool> _answer(Object value) => switch (value) {
  _never => Completer<bool>().future,
  final Exception failure => Future.error(failure),
  final bool answer => Future.value(answer),
  _ => throw StateError('A scripted answer is a bool, a failure or never.'),
};

const Map<BiometricReason, String> _texts = {
  BiometricReason.unlockApp: 'Unlock Boardroom',
  BiometricReason.confirmVote: 'Confirm your vote',
};
const String _cancelLabel = 'Annuler';

({
  _ScriptedPlatform platform,
  DeviceBiometricGate gate,
  FakeMonitoring monitoring,
})
_aGate([_ScriptedPlatform? scripted, bool allowDevicePasscode = false]) {
  final platform = scripted ?? _ScriptedPlatform();
  final monitoring = FakeMonitoring();
  final gate = DeviceBiometricGate(
    api: platform,
    promptText: (reason) =>
        PromptText(message: _texts[reason]!, cancelLabel: _cancelLabel),
    monitoring: monitoring,
    allowDevicePasscode: allowDevicePasscode,
    timeoutMillis: 20,
  );
  return (platform: platform, gate: gate, monitoring: monitoring);
}

// Every outcome of the platform layer, with the error of the domain it becomes.
const List<(LocalAuthenticationError, BiometricErrorCode)> _outcomes = [
  (LocalAuthenticationError.authenticationFailed, BiometricErrorCode.failed),
  (LocalAuthenticationError.unableToProcess, BiometricErrorCode.failed),
  (LocalAuthenticationError.unknown, BiometricErrorCode.failed),
  (LocalAuthenticationError.lockout, BiometricErrorCode.lockedOut),
  (LocalAuthenticationError.notEnrolled, BiometricErrorCode.notEnrolled),
  (LocalAuthenticationError.notAvailable, BiometricErrorCode.unavailable),
  (LocalAuthenticationError.passcodeNotSet, BiometricErrorCode.unavailable),
  (LocalAuthenticationError.noSpace, BiometricErrorCode.unavailable),
  (LocalAuthenticationError.invalidContext, BiometricErrorCode.unavailable),
  (LocalAuthenticationError.userCancel, BiometricErrorCode.cancelled),
  (LocalAuthenticationError.appCancel, BiometricErrorCode.cancelled),
  (LocalAuthenticationError.systemCancel, BiometricErrorCode.cancelled),
  (LocalAuthenticationError.userFallback, BiometricErrorCode.cancelled),
  (LocalAuthenticationError.timeout, BiometricErrorCode.cancelled),
];

AppError _errorOfCode(BiometricErrorCode code) => switch (code) {
  BiometricErrorCode.unavailable => biometricUnavailable(),
  BiometricErrorCode.notEnrolled => biometricNotEnrolled(),
  BiometricErrorCode.cancelled => biometricCancelled(),
  BiometricErrorCode.failed => biometricFailed(),
  BiometricErrorCode.lockedOut => biometricLockedOut(),
};

void main() {
  group('DeviceBiometricGate', () {
    group('checkAvailability', () {
      test(
        'succeeds when the device has the hardware and the user enrolled',
        () async {
          final (:gate, platform: _, monitoring: _) = _aGate();

          expect(await gate.checkAvailability(), equals(ok<void>(null)));
        },
      );

      test('is unavailable without the hardware, and does not ask about the '
          'enrolment', () async {
        final (:gate, :platform, monitoring: _) = _aGate();
        platform.hardware = false;

        expect(
          await gate.checkAvailability(),
          equals(err(biometricUnavailable())),
        );
        expect(platform.enrolmentQuestions, equals(0));
      });

      test(
        'is not enrolled when there is the hardware and nothing enrolled',
        () async {
          final (:gate, :platform, monitoring: _) = _aGate();
          platform.enrolled = false;

          expect(
            await gate.checkAvailability(),
            equals(err(biometricNotEnrolled())),
          );
        },
      );

      for (final (name, breakIt)
          in <(String, void Function(_ScriptedPlatform))>[
            (
              'the question about the hardware throws',
              (platform) => platform.hardware = Exception('no module'),
            ),
            (
              'the question about the enrolment throws',
              (platform) => platform.enrolled = Exception('no module'),
            ),
            (
              'the question about the hardware never answers',
              (platform) => platform.hardware = _never,
            ),
            (
              'the question about the enrolment never answers',
              (platform) => platform.enrolled = _never,
            ),
          ]) {
        test('is unavailable, and settles, when $name', () async {
          final (:gate, :platform, monitoring: _) = _aGate();
          breakIt(platform);

          expect(
            await gate.checkAvailability(),
            equals(err(biometricUnavailable())),
          );
        });
      }
    });

    group('authenticate', () {
      test('succeeds when the user is recognised', () async {
        final (:gate, platform: _, monitoring: _) = _aGate();

        expect(
          await gate.authenticate(BiometricReason.unlockApp),
          equals(ok<void>(null)),
        );
      });

      for (final (reason, text) in [
        (BiometricReason.unlockApp, 'Unlock Boardroom'),
        (BiometricReason.confirmVote, 'Confirm your vote'),
      ]) {
        test(
          'shows the text the app gives for the reason ${reason.value}',
          () async {
            final (:gate, :platform, monitoring: _) = _aGate();

            await gate.authenticate(reason);

            expect(
              platform.prompts.map((prompt) => prompt.promptMessage),
              equals([text]),
            );
          },
        );
      }

      test(
        'asks for the text each time, so that it follows the language of the '
        'moment',
        () async {
          var language = 'en';
          final platform = _ScriptedPlatform();
          final gate = DeviceBiometricGate(
            api: platform,
            promptText: (_) => PromptText(
              message: language == 'en' ? 'Unlock' : 'Déverrouiller',
              cancelLabel: language == 'en' ? 'Cancel' : 'Annuler',
            ),
            monitoring: FakeMonitoring(),
            allowDevicePasscode: false,
          );

          await gate.authenticate(BiometricReason.unlockApp);
          language = 'fr';
          await gate.authenticate(BiometricReason.unlockApp);

          expect(
            platform.prompts.map((prompt) => prompt.promptMessage),
            equals(['Unlock', 'Déverrouiller']),
          );
        },
      );

      test('gives the prompt the label of its cancel button in the language of '
          'the moment', () async {
        var language = 'en';
        final platform = _ScriptedPlatform();
        final gate = DeviceBiometricGate(
          api: platform,
          promptText: (_) => PromptText(
            message: 'm',
            cancelLabel: language == 'en' ? 'Cancel' : 'Annuler',
          ),
          monitoring: FakeMonitoring(),
          allowDevicePasscode: false,
        );

        await gate.authenticate(BiometricReason.unlockApp);
        language = 'fr';
        await gate.authenticate(BiometricReason.unlockApp);

        expect(
          platform.prompts.map((prompt) => prompt.cancelLabel),
          equals(['Cancel', 'Annuler']),
        );
      });

      for (final reason in [
        BiometricReason.unlockApp,
        BiometricReason.confirmVote,
      ]) {
        test('asks for strong biometrics on Android, for the reason '
            '${reason.value}', () async {
          final (:gate, :platform, monitoring: _) = _aGate();

          await gate.authenticate(reason);

          expect(
            platform.prompts.map((prompt) => prompt.biometricsSecurityLevel),
            equals([BiometricsSecurityLevel.strong]),
          );
        });
      }

      for (final (accepted, disabled) in [(false, true), (true, false)]) {
        test('with the passcode accepted as a fallback = $accepted, tells the '
            'platform to disable it = $disabled', () async {
          final (:gate, :platform, monitoring: _) = _aGate(
            _ScriptedPlatform(),
            accepted,
          );

          await gate.authenticate(BiometricReason.confirmVote);

          expect(
            platform.prompts.first.disableDeviceFallback,
            equals(disabled),
          );
        });
      }

      for (final (outcome, code) in _outcomes) {
        test('turns the outcome ${outcome.value} into ${code.value}', () async {
          final (:gate, :platform, monitoring: _) = _aGate();
          platform.outcome = LocalAuthenticationResult.failed(outcome.value);

          expect(
            await gate.authenticate(BiometricReason.unlockApp),
            equals(err(_errorOfCode(code))),
          );
        });
      }

      for (final name in [
        'constructor',
        'toString',
        'hasOwnProperty',
        '__proto__',
        'valueOf',
      ]) {
        test('refuses the outcome $name, which is the name of a property every '
            'object has and not a code', () async {
          final (:gate, :platform, monitoring: _) = _aGate();
          platform.outcome = LocalAuthenticationResult.failed(name);

          expect(
            await gate.authenticate(BiometricReason.unlockApp),
            equals(err(biometricFailed())),
          );
        });
      }

      test('does not take an object without success for a success', () async {
        final (:gate, :platform, monitoring: _) = _aGate();
        platform.outcome = const LocalAuthenticationResult(success: false);

        expect(
          await gate.authenticate(BiometricReason.unlockApp),
          equals(err(biometricFailed())),
        );
      });

      test('takes a build without the iOS usage description for unavailable '
          'biometrics, and reports it as a configuration error', () async {
        final (:gate, :platform, :monitoring) = _aGate();
        platform.outcome = LocalAuthenticationResult.failed(
          LocalAuthenticationError.missingUsageDescription.value,
        );

        expect(
          await gate.authenticate(BiometricReason.unlockApp),
          equals(err(biometricUnavailable())),
        );
        expect(
          monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.biometricMisconfigured,
              error: biometricUnavailable(),
              attributes: null,
            ),
          ]),
        );
      });

      test(
        "reports nothing for the outcomes that are the user's doing",
        () async {
          final (:gate, :platform, :monitoring) = _aGate();
          platform.outcome = LocalAuthenticationResult.failed(
            LocalAuthenticationError.userCancel.value,
          );

          await gate.authenticate(BiometricReason.unlockApp);

          expect(monitoring.errors, isEmpty);
        },
      );

      test(
        'refuses an outcome it does not know, instead of granting it',
        () async {
          final (:gate, :platform, monitoring: _) = _aGate();
          platform.outcome = const LocalAuthenticationResult.failed(
            'something_new',
          );

          expect(
            await gate.authenticate(BiometricReason.unlockApp),
            equals(err(biometricFailed())),
          );
        },
      );

      test(
        'is unavailable, and does not reject, when the platform throws',
        () async {
          final (:gate, :platform, monitoring: _) = _aGate();
          platform.outcome = Exception('no activity');

          expect(
            await gate.authenticate(BiometricReason.unlockApp),
            equals(err(biometricUnavailable())),
          );
        },
      );

      test('is unavailable, and does not reject, when the text of the prompt '
          'cannot be had', () async {
        final platform = _ScriptedPlatform();
        final gate = DeviceBiometricGate(
          api: platform,
          promptText: (_) => throw Exception('no translation'),
          monitoring: FakeMonitoring(),
          allowDevicePasscode: false,
        );

        expect(
          await gate.authenticate(BiometricReason.unlockApp),
          equals(err(biometricUnavailable())),
        );
        expect(platform.prompts, isEmpty);
      });
    });
  });
}
