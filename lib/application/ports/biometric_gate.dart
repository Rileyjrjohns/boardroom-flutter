import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/constants.dart';
import 'package:boardroom/domain/shared/result.dart';

/// Why the user is asked for a biometric proof. The application names a
/// reason; the adapter (or the presentation) turns it into the text of the
/// system prompt, in the language of the user. No text travels through this
/// port.
enum BiometricReason implements StableValue {
  /// The user unlocks the app (restored session, return after the grace
  /// period).
  unlockApp('unlockApp'),

  /// The user confirms a vote before it is cast.
  confirmVote('confirmVote');

  new(this.value);

  @override
  final String value;
}

/// The biometric check of the device (fingerprint, face).
///
/// It proves that a person enrolled on this device is present. It does not
/// prove that this person is the user of the session: a device may hold several
/// fingerprints. Whether the device passcode is accepted as a fallback when the
/// biometrics fail is a setting of the adapter, chosen at the composition root
/// (a board that wants biometrics only turns it off); nothing in this port or
/// in the application depends on the choice.
///
/// Contract: no method throws. A refusal of the user is an error `Result`, not
/// an exception. A prompt waits for the user, so its duration is theirs, but it
/// always ends with a result (`cancelled` included); a check of the capability
/// settles in bounded time.
abstract interface class BiometricGate {
  /// Succeeds when biometrics can be used right now: hardware present, at least
  /// one enrolment.
  Future<Result<void, BiometricAvailabilityError>> checkAvailability();

  /// Shows the system prompt for a reason. Succeeds only when the user is
  /// recognised.
  Future<Result<void, BiometricError>> authenticate(BiometricReason reason);
}
