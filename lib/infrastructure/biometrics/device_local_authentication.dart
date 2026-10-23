// `local_auth_android` and `local_auth_darwin` are the platform halves of
// `local_auth`, and hold the classes that carry the label of the cancel button
// (`AndroidAuthMessages`, `IOSAuthMessages`) which `local_auth` does not
// re-export. They are listed in pubspec.yaml as direct dependencies of the app.

import 'package:boardroom/infrastructure/biometrics/device_biometric_gate.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

/// What iOS shows as the label of the fallback button of the prompt. Empty,
/// the system hides the button.
const String _noFallbackTitle = '';

/// The hint of the prompt of Android, shown under its title. Empty, nothing is
/// shown: `local_auth_android` would otherwise fill it with an English text of
/// its own, and no text of the prompt is written in this layer.
const String _noSignInHint = '';

/// What `local_auth` says when a prompt did not succeed, as the code of the
/// outcomes the gate understands (`LocalAuthenticationError`).
///
/// The switch lists every code of `local_auth`, with no default: a code added
/// by an update of the package fails the analysis here instead of being
/// treated as something it is not.
LocalAuthenticationError errorOfException(
  LocalAuthExceptionCode code,
) => switch (code) {
  LocalAuthExceptionCode.userCanceled => LocalAuthenticationError.userCancel,
  LocalAuthExceptionCode.timeout => LocalAuthenticationError.timeout,
  LocalAuthExceptionCode.systemCanceled =>
    LocalAuthenticationError.systemCancel,
  LocalAuthExceptionCode.userRequestedFallback =>
    LocalAuthenticationError.userFallback,
  LocalAuthExceptionCode.noBiometricsEnrolled =>
    LocalAuthenticationError.notEnrolled,
  LocalAuthExceptionCode.noBiometricHardware ||
  LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
    LocalAuthenticationError.notAvailable,
  LocalAuthExceptionCode.noCredentialsSet =>
    LocalAuthenticationError.passcodeNotSet,
  LocalAuthExceptionCode.temporaryLockout ||
  LocalAuthExceptionCode.biometricLockout => LocalAuthenticationError.lockout,
  LocalAuthExceptionCode.uiUnavailable =>
    LocalAuthenticationError.invalidContext,
  LocalAuthExceptionCode.deviceError => LocalAuthenticationError.noSpace,
  LocalAuthExceptionCode.authInProgress =>
    LocalAuthenticationError.unableToProcess,
  LocalAuthExceptionCode.unknownError => LocalAuthenticationError.unknown,
};

/// Whether the biometrics a device reports include one that counts as strong.
///
/// Android reports a classification (`weak` for Class 2, `strong` for Class 3,
/// and a Class 3 biometric is both); iOS reports the kind of biometric (face,
/// fingerprint), all of them strong. A device whose only biometric is `weak`
/// is a device without the kind the app asks for.
bool hasStrongBiometric(Iterable<BiometricType> enrolled) =>
    enrolled.any((type) => type != BiometricType.weak);

/// The three calls of `local_auth` that the biometric gate uses. They are
/// handed over as they are, with two translations: the exceptions of
/// `local_auth` become the codes the gate understands, and a device whose only
/// biometrics are weak is not enrolled (see [hasStrongBiometric]). Anything
/// else `local_auth` throws is left to the gate, which turns it into
/// `biometricUnavailable`.
///
/// `local_auth` has no option to ask Android for strong biometrics only: the
/// prompt takes a strong or a weak one. The check on the enrolment above is
/// what keeps a device with a weak biometric alone out (see
/// `docs/parity/open-questions.md`). The prompt itself has been shown on no
/// device by the tests.
final class DeviceLocalAuthentication implements LocalAuthenticationApi {
  /// Creates the adapter over [auth], the plugin by default.
  new([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> hasHardware() => _auth.canCheckBiometrics;

  @override
  Future<bool> isEnrolled() async =>
      hasStrongBiometric(await _auth.getAvailableBiometrics());

  @override
  Future<LocalAuthenticationResult> authenticate(
    AuthenticationPrompt prompt,
  ) async {
    try {
      final recognised = await _auth.authenticate(
        localizedReason: prompt.promptMessage,
        authMessages: [
          IOSAuthMessages(
            cancelButton: prompt.cancelLabel,
            localizedFallbackTitle: prompt.disableDeviceFallback
                ? _noFallbackTitle
                : null,
          ),
          // The title of the prompt of Android is the message, as in React
          // Native; the plugin would otherwise write "Authentication required"
          // in English, whatever the language of the app.
          AndroidAuthMessages(
            cancelButton: prompt.cancelLabel,
            signInTitle: prompt.promptMessage,
            signInHint: _noSignInHint,
          ),
        ],
        biometricOnly: prompt.disableDeviceFallback,
      );
      return recognised
          ? const .succeeded()
          : .failed(LocalAuthenticationError.authenticationFailed.value);
    } on LocalAuthException catch (exception) {
      return .failed(errorOfException(exception.code).value);
    }
  }
}
