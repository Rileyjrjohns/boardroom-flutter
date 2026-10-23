// The test reads the messages the adapter hands to `local_auth` through their
// `args`, which is how the platform halves read them; naming the classes would
// need the two platform packages. `local_auth` is the only adapter package it
// imports.
import 'package:boardroom/infrastructure/biometrics/device_biometric_gate.dart';
import 'package:boardroom/infrastructure/biometrics/device_local_authentication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

/// `local_auth` with answers the test sets, which remembers what it was asked.
final class _FakeLocalAuthentication implements LocalAuthentication {
  bool hardware = true;
  List<BiometricType> enrolled = const [];
  Object recognised = true;
  final List<String> asked = [];
  final List<Map<String, Object?>> prompts = [];

  @override
  Future<bool> get canCheckBiometrics async {
    asked.add('canCheckBiometrics');
    return hardware;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    asked.add('getAvailableBiometrics');
    return enrolled;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<dynamic> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    asked.add('authenticate');
    prompts.add({
      'localizedReason': localizedReason,
      'messages': [
        for (final message in authMessages)
          (message as dynamic).args as Map<String, String>,
      ],
      'biometricOnly': biometricOnly,
      'sensitiveTransaction': sensitiveTransaction,
      'persistAcrossBackgrounding': persistAcrossBackgrounding,
    });
    return switch (recognised) {
      final bool answer => answer,
      final Object failure => await Future<bool>.error(failure),
    };
  }

  @override
  Future<bool> isDeviceSupported() => throw UnimplementedError();

  @override
  Future<bool> stopAuthentication() => throw UnimplementedError();
}

const AuthenticationPrompt _prompt = AuthenticationPrompt(
  promptMessage: 'Unlock',
  cancelLabel: 'Cancel',
  disableDeviceFallback: true,
  biometricsSecurityLevel: BiometricsSecurityLevel.strong,
);

void main() {
  group('DeviceLocalAuthentication', () {
    test('asks the module about the hardware and the enrolment, and hands the '
        'answers over', () async {
      final auth = _FakeLocalAuthentication()
        ..hardware = true
        ..enrolled = const [BiometricType.fingerprint];
      final platform = DeviceLocalAuthentication(auth);

      expect(await platform.hasHardware(), isTrue);
      expect(await platform.isEnrolled(), isTrue);
      expect(
        auth.asked,
        equals(['canCheckBiometrics', 'getAvailableBiometrics']),
      );
    });

    test(
      'shows the prompt with the options it is given, and nothing else',
      () async {
        final auth = _FakeLocalAuthentication();

        final outcome = await DeviceLocalAuthentication(auth)
            .authenticate(_prompt);

        expect(outcome, equals(const LocalAuthenticationResult.succeeded()));
        expect(auth.asked, equals(['authenticate']));
        expect(
          auth.prompts,
          equals([
            {
              'localizedReason': 'Unlock',
              // The label of the cancel button goes to both platforms, and iOS
              // hides its fallback button when the passcode is refused.
              'messages': [
                {'okButton': 'Cancel', 'localizedFallbackTitle': ''},
                // The title of the Android prompt is the message of the app,
                // and its hint is empty: no text of the plugin (in English)
                // is left in it.
                {
                  'biometricHint': '',
                  'cancelButton': 'Cancel',
                  'signInTitle': 'Unlock',
                },
              ],
              'biometricOnly': true,
              'sensitiveTransaction': true,
              'persistAcrossBackgrounding': false,
            },
          ]),
        );
      },
    );

    test('lets the passcode in, and keeps the fallback button of iOS, when '
        'the prompt does not refuse it', () async {
      final auth = _FakeLocalAuthentication();
      const open = AuthenticationPrompt(
        promptMessage: 'Unlock',
        cancelLabel: 'Cancel',
        disableDeviceFallback: false,
        biometricsSecurityLevel: BiometricsSecurityLevel.strong,
      );

      await DeviceLocalAuthentication(auth).authenticate(open);

      expect(auth.prompts.single['biometricOnly'], isFalse);
      expect(
        (auth.prompts.single['messages']! as List<Map<String, String>>).first,
        equals({'okButton': 'Cancel'}),
      );
    });

    test(
      'says the user was not recognised when the plugin says false',
      () async {
        final auth = _FakeLocalAuthentication()..recognised = false;

        expect(
          await DeviceLocalAuthentication(auth).authenticate(_prompt),
          equals(
            LocalAuthenticationResult.failed(
              LocalAuthenticationError.authenticationFailed.value,
            ),
          ),
        );
      },
    );

    // Every exception of the plugin, with the outcome it becomes.
    const expectedOutcomes = <LocalAuthExceptionCode, LocalAuthenticationError>{
      LocalAuthExceptionCode.authInProgress:
          LocalAuthenticationError.unableToProcess,
      LocalAuthExceptionCode.uiUnavailable:
          LocalAuthenticationError.invalidContext,
      LocalAuthExceptionCode.userCanceled: LocalAuthenticationError.userCancel,
      LocalAuthExceptionCode.timeout: LocalAuthenticationError.timeout,
      LocalAuthExceptionCode.systemCanceled:
          LocalAuthenticationError.systemCancel,
      LocalAuthExceptionCode.noCredentialsSet:
          LocalAuthenticationError.passcodeNotSet,
      LocalAuthExceptionCode.noBiometricsEnrolled:
          LocalAuthenticationError.notEnrolled,
      LocalAuthExceptionCode.noBiometricHardware:
          LocalAuthenticationError.notAvailable,
      LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
          LocalAuthenticationError.notAvailable,
      LocalAuthExceptionCode.temporaryLockout: LocalAuthenticationError.lockout,
      LocalAuthExceptionCode.biometricLockout: LocalAuthenticationError.lockout,
      LocalAuthExceptionCode.userRequestedFallback:
          LocalAuthenticationError.userFallback,
      LocalAuthExceptionCode.deviceError: LocalAuthenticationError.noSpace,
      LocalAuthExceptionCode.unknownError: LocalAuthenticationError.unknown,
    };

    test('knows every exception of the plugin', () {
      expect(
        expectedOutcomes.keys,
        unorderedEquals(LocalAuthExceptionCode.values),
      );
    });

    for (final MapEntry(key: code, value: outcome)
        in expectedOutcomes.entries) {
      test('turns the exception ${code.name} of the plugin into the outcome '
          '${outcome.value}', () async {
        final auth = _FakeLocalAuthentication()
          ..recognised = LocalAuthException(code: code);

        expect(
          await DeviceLocalAuthentication(auth).authenticate(_prompt),
          equals(LocalAuthenticationResult.failed(outcome.value)),
        );
      });
    }

    test('lets anything else the plugin throws go to the gate', () async {
      final auth = _FakeLocalAuthentication()
        ..recognised = Exception('no channel');

      await expectLater(
        DeviceLocalAuthentication(auth).authenticate(_prompt),
        throwsA(isA<Exception>()),
      );
    });

    group('isEnrolled', () {
      for (final (name, enrolled, expected)
          in <(String, List<BiometricType>, bool)>[
            ('nothing enrolled', const [], false),
            ('a fingerprint', const [BiometricType.fingerprint], true),
            ('a face', const [BiometricType.face], true),
            (
              'only a weak biometric, a camera-based face unlock for example',
              const [BiometricType.weak],
              false,
            ),
            (
              'a strong biometric, which Android reports as weak too',
              const [BiometricType.weak, BiometricType.strong],
              true,
            ),
          ]) {
        test('is $expected for $name', () async {
          final auth = _FakeLocalAuthentication()..enrolled = enrolled;

          expect(
            await DeviceLocalAuthentication(auth).isEnrolled(),
            equals(expected),
          );
        });
      }
    });
  });
}
