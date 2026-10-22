import 'package:boardroom/application/ports/biometric_gate.dart';
import 'package:boardroom/application/shared/app_lock.dart';
import 'package:boardroom/application/shared/confirm_with_biometrics.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';

/// What [UnlockApp] needs.
abstract interface class UnlockAppDeps {
  /// The biometrics of the device.
  BiometricGate get biometricGate;

  /// The instance shared by every use case: see [AppLock].
  AppLock get appLock;
}

/// Unlocks the app with a biometric proof, and opens the [AppLock]: until it
/// succeeds, no use case returns data to the user. It fails closed: when the
/// biometrics cannot be used (`biometricUnavailable`, `biometricNotEnrolled`),
/// or the user cannot be recognised, the app stays locked and nothing else
/// unlocks it. On a device where they can never be used, the only way forward
/// is to sign out and sign in again (see `RestoreSession`).
///
/// The biometrics prove that a person enrolled on this device is present, not
/// that this person is the user of the session: the device may hold several
/// fingerprints. That is the limit of the lock, and the reason the session
/// itself expires.
final class UnlockApp {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final UnlockAppDeps _deps;

  /// Asks for the biometric proof and, when it is given, opens the lock.
  Future<Result<void, BiometricError>> execute() async {
    final confirmed = await confirmWithBiometrics(
      _deps.biometricGate,
      BiometricReason.unlockApp,
    );
    if (isOk(confirmed)) {
      _deps.appLock.unlock();
    }
    return confirmed;
  }
}
