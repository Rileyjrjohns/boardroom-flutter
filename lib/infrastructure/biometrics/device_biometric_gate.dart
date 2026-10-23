import 'package:boardroom/application/ports/biometric_gate.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/constants.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/infrastructure/shared/attempt.dart';
import 'package:meta/meta.dart';

/// How long the questions about the capability (hardware, enrolment) may take.
const int defaultCapabilityTimeoutMillis = 10000;

/// What the platform is told about the kind of biometrics that count.
enum BiometricsSecurityLevel implements StableValue {
  /// Any biometric the platform accepts, a camera-based face unlock included
  /// (a Class 2 biometric on Android).
  weak('weak'),

  /// Only a fingerprint or a 3D face scan (a Class 3 biometric on Android).
  strong('strong');

  new(this.value);

  @override
  final String value;
}

/// Only a fingerprint or a 3D face scan opens the app and confirms a vote. On
/// Android, `weak` would also take a camera-based face unlock (a Class 2
/// biometric), which a photograph can fool; iOS has no weak biometric, and
/// ignores the option.
const BiometricsSecurityLevel biometricSecurityLevel =
    BiometricsSecurityLevel.strong;

/// Every outcome a prompt that did not succeed can have, as the platform
/// layer names it. It is the list of the codes the gate understands, each one
/// with the biometric error of the domain it becomes (see
/// [DeviceBiometricGate]).
enum LocalAuthenticationError implements StableValue {
  /// The biometrics did not recognise the user.
  authenticationFailed('authentication_failed'),

  /// The platform could not process the attempt.
  unableToProcess('unable_to_process'),

  /// The platform failed for a reason it does not name.
  unknown('unknown'),

  /// Too many failed attempts: the biometrics are locked.
  lockout('lockout'),

  /// The device has the hardware and nothing enrolled.
  notEnrolled('not_enrolled'),

  /// The device cannot do it (no hardware, or not reachable).
  notAvailable('not_available'),

  /// The device has no passcode, which the platform requires.
  passcodeNotSet('passcode_not_set'),

  /// The device has no room to run the check.
  noSpace('no_space'),

  /// The prompt cannot be shown (no screen, no activity, a context that is no
  /// longer valid).
  invalidContext('invalid_context'),

  /// The user cancelled the prompt.
  userCancel('user_cancel'),

  /// The app cancelled the prompt.
  appCancel('app_cancel'),

  /// The system cancelled the prompt (the app went to the background).
  systemCancel('system_cancel'),

  /// The user chose the fallback of the prompt instead of the biometrics.
  userFallback('user_fallback'),

  /// The prompt timed out.
  timeout('timeout'),

  /// What iOS says when `NSFaceIDUsageDescription` is missing from the build.
  /// Face ID cannot be asked for: it is a mistake of the build, not of the
  /// user.
  missingUsageDescription('missing_usage_description');

  new(this.value);

  @override
  final String value;
}

/// What the system prompt says: the reason it is shown and the label of the
/// button that cancels.
@immutable
final class PromptText {
  /// Creates the text of a prompt.
  const new({required this.message, required this.cancelLabel});

  /// Why the user is asked, in the language of the user.
  final String message;

  /// The label of the cancel button of the prompt, in the language of the
  /// user.
  final String cancelLabel;

  @override
  bool operator ==(Object other) =>
      other is PromptText &&
      other.message == message &&
      other.cancelLabel == cancelLabel;

  @override
  int get hashCode => Object.hash(message, cancelLabel);

  @override
  String toString() => 'PromptText($message, $cancelLabel)';
}

/// What the gate asks the platform to show.
@immutable
final class AuthenticationPrompt {
  /// Creates the description of a prompt.
  const new({
    required this.promptMessage,
    required this.cancelLabel,
    required this.disableDeviceFallback,
    required this.biometricsSecurityLevel,
  });

  /// The reason shown to the user.
  final String promptMessage;

  /// The label of the button that cancels.
  final String cancelLabel;

  /// Whether the passcode of the device is refused when the biometrics do not
  /// recognise the user.
  final bool disableDeviceFallback;

  /// Which biometrics count.
  final BiometricsSecurityLevel biometricsSecurityLevel;

  @override
  bool operator ==(Object other) =>
      other is AuthenticationPrompt &&
      other.promptMessage == promptMessage &&
      other.cancelLabel == cancelLabel &&
      other.disableDeviceFallback == disableDeviceFallback &&
      other.biometricsSecurityLevel == biometricsSecurityLevel;

  @override
  int get hashCode => Object.hash(
    promptMessage,
    cancelLabel,
    disableDeviceFallback,
    biometricsSecurityLevel,
  );

  @override
  String toString() =>
      'AuthenticationPrompt(${biometricsSecurityLevel.value}, '
      'disableDeviceFallback: $disableDeviceFallback)';
}

/// What a prompt ended with: a success, or the code of the failure as the
/// platform layer named it.
@immutable
final class LocalAuthenticationResult {
  /// Creates the outcome of a prompt. [error] is the code of a failure
  /// (`LocalAuthenticationError.value`), as received: a code a newer platform
  /// layer sends may be one the gate does not know.
  const new({required this.success, this.error});

  /// The user was recognised.
  const new succeeded() : this(success: true);

  /// The user was not recognised, for the reason [error].
  const new failed(String? error) : this(success: false, error: error);

  /// Whether the user was recognised.
  final bool success;

  /// Why not, when it did not succeed.
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is LocalAuthenticationResult &&
      other.success == success &&
      other.error == error;

  @override
  int get hashCode => Object.hash(success, error);

  @override
  String toString() => 'LocalAuthenticationResult($success, $error)';
}

/// What the adapter asks of the platform: the three calls of the platform
/// layer it uses.
abstract interface class LocalAuthenticationApi {
  /// Whether the device has biometric hardware.
  Future<bool> hasHardware();

  /// Whether a biometric is enrolled.
  Future<bool> isEnrolled();

  /// Shows the system prompt and waits for the user.
  Future<LocalAuthenticationResult> authenticate(AuthenticationPrompt prompt);
}

/// The text of the system prompt for a reason: see
/// [DeviceBiometricGate.new].
typedef PromptTextOf = PromptText Function(BiometricReason reason);

/// The biometric error of the domain each outcome of the platform becomes.
///
/// Every outcome has an entry (the enum lists them all), so that a code added
/// to it fails the switch below instead of being treated as something it is
/// not. A code the platform sends that is not in the enum at run time (a newer
/// platform layer than this one) is `biometricFailed`: the authentication is
/// refused, never granted.
BiometricError _errorOf(LocalAuthenticationError outcome) => switch (outcome) {
  LocalAuthenticationError.missingUsageDescription => biometricUnavailable(),
  LocalAuthenticationError.authenticationFailed ||
  LocalAuthenticationError.unableToProcess ||
  LocalAuthenticationError.unknown => biometricFailed(),
  LocalAuthenticationError.lockout => biometricLockedOut(),
  LocalAuthenticationError.notEnrolled => biometricNotEnrolled(),
  LocalAuthenticationError.notAvailable ||
  LocalAuthenticationError.passcodeNotSet ||
  LocalAuthenticationError.noSpace ||
  LocalAuthenticationError.invalidContext => biometricUnavailable(),
  LocalAuthenticationError.userCancel ||
  LocalAuthenticationError.appCancel ||
  LocalAuthenticationError.systemCancel ||
  LocalAuthenticationError.userFallback ||
  LocalAuthenticationError.timeout => biometricCancelled(),
};

/// The biometric check of the device, over the platform layer
/// ([LocalAuthenticationApi]). It maps every outcome of the platform to the
/// biometric errors of the domain and never throws: a platform that throws, or
/// does not answer a question about the capability in time, is
/// `biometricUnavailable`, which the application treats as the biometrics not
/// being usable (it fails closed).
///
/// The biometrics prove that a person enrolled on the device is present, not
/// that it is the user of the session. Whether the passcode of the device
/// stands in when they fail is the setting `allowDevicePasscode`. Only strong
/// biometrics count on Android ([biometricSecurityLevel]), and only an outcome
/// that says `success: true` is a success. A build that lacks the usage
/// description iOS needs to ask for Face ID is `biometricUnavailable`, and is
/// captured by the monitoring as the mistake of the build it is.
final class DeviceBiometricGate implements BiometricGate {
  /// Creates the gate over `api`.
  ///
  /// `promptText` gives the text of the system prompt for a reason, in the
  /// language of the user: its message and the label of its cancel button,
  /// which the system would otherwise write in its own language. The adapter
  /// cannot import the presentation, where the translations are: the
  /// composition root hands the function over, and it reads the current
  /// language each time it is called.
  ///
  /// `monitoring` is told when the build is missing what the platform needs to
  /// ask for the biometrics. `allowDevicePasscode` is whether the passcode of
  /// the device is accepted when the biometrics do not recognise the user: a
  /// setting of the composition root. `timeoutMillis` defaults to
  /// [defaultCapabilityTimeoutMillis].
  const new({
    required this._api,
    required this._promptText,
    required this._monitoring,
    required this._allowDevicePasscode,
    this._timeoutMillis = defaultCapabilityTimeoutMillis,
  });

  final LocalAuthenticationApi _api;
  final PromptTextOf _promptText;
  final Monitoring _monitoring;
  final bool _allowDevicePasscode;
  final int _timeoutMillis;

  @override
  Future<Result<void, BiometricAvailabilityError>> checkAvailability() async {
    final hardware = await attempt(_api.hasHardware, _timeoutMillis);
    if (hardware case Err() || Ok(value: false)) {
      return err(biometricUnavailable());
    }
    switch (await attempt(_api.isEnrolled, _timeoutMillis)) {
      case Err():
        return err(biometricUnavailable());
      case Ok(value: true):
        return ok<void>(null);
      case Ok():
        return err(biometricNotEnrolled());
    }
  }

  @override
  Future<Result<void, BiometricError>> authenticate(
    BiometricReason reason,
  ) async {
    try {
      final PromptText(:message, :cancelLabel) = _promptText(reason);
      // The prompt waits for the person: it has no time limit of ours, and
      // always ends.
      final outcome = await _api.authenticate(
        AuthenticationPrompt(
          promptMessage: message,
          cancelLabel: cancelLabel,
          disableDeviceFallback: !_allowDevicePasscode,
          biometricsSecurityLevel: biometricSecurityLevel,
        ),
      );
      if (outcome.success) {
        return ok<void>(null);
      }
      final code = findConstant(
        LocalAuthenticationError.values,
        outcome.error ?? '',
      );
      final error = code == null ? biometricFailed() : _errorOf(code);
      if (code == LocalAuthenticationError.missingUsageDescription) {
        _monitoring.captureError(MonitoringEvent.biometricMisconfigured, error);
      }
      return err(error);
    } on Object catch (_) {
      return err(biometricUnavailable());
    }
  }
}
