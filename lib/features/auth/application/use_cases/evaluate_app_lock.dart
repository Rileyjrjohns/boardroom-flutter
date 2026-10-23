import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/auth/application/ports/auth_session.dart';
import 'package:boardroom/features/auth/application/session/app_lock.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/domain/policies/app_lock.dart';
import 'package:boardroom/features/auth/domain/policies/session_expiry.dart';

/// What [EvaluateAppLock] needs.
abstract interface class EvaluateAppLockDeps {
  /// The stored session.
  AuthSession get auth;

  /// The clock the time away is measured by.
  Clock get clock;

  /// Configuration, set once by the composition root: how long the app may stay
  /// in the background.
  DurationMillis get gracePeriod;

  /// The instance shared by every use case: see [AppLock].
  AppLock get appLock;
}

/// Decides, when the app returns from the background, whether the user must
/// unlock it with the biometrics (see [isUnlockRequired]). Succeeds with `true`
/// when they must, and then the [AppLock] is closed, so that no use case serves
/// anything until `UnlockApp` succeeds: the answer is the information for the
/// screen, the lock is the enforcement. Nobody signed in, or a session that has
/// expired, means there is nothing to lock.
///
/// When the stored session cannot be read, the lock is closed too, and the
/// error is returned: the use case cannot say there is nothing to protect, so
/// it fails closed.
final class EvaluateAppLock {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final EvaluateAppLockDeps _deps;

  /// Evaluates the lock. [backgroundedAt] is when the app went to the
  /// background; the presentation records it.
  Future<Result<bool, StorageReadFailedError>> execute({
    required Instant backgroundedAt,
  }) async {
    final EvaluateAppLockDeps(:auth, :clock, :gracePeriod, :appLock) = _deps;

    final Session? session;
    switch (await auth.current()) {
      case Err(:final error):
        appLock.lock();
        return err(error);
      case Ok(:final value):
        session = value;
    }

    final now = clock.now();
    final required = isUnlockRequired(
      AppLockInput(
        backgroundedAt: backgroundedAt,
        now: now,
        gracePeriod: gracePeriod,
        hasSession: session != null && !isSessionExpired(session, now),
      ),
    );
    if (required) {
      appLock.lock();
    }
    return ok(required);
  }
}
