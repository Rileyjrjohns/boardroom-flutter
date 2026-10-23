import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/auth/application/session/end_session.dart';
import 'package:boardroom/features/auth/application/session/purge_caches.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/policies/session_expiry.dart';

/// What the guard of a use case fails with when there is no usable session: not
/// authenticated, session expired, app locked, or a stored session that cannot
/// be read. The members are [NotAuthenticatedError], [SessionExpiredError],
/// [AppLockedError] and [StorageReadFailedError].
typedef SessionRequiredError = AppError;

/// What [requireSession] and [requireSameUser] need. It is what [closeSession]
/// needs (the session, the lock shared by every use case, and the purgers of
/// the data a session leaves, which run when a session is found expired: see
/// [requireSession]) plus the clock.
abstract interface class RequireSessionDeps implements EndSessionDeps {
  /// The clock the expiry of the session is judged by.
  Clock get clock;
}

/// The session of the signed-in user, for a use case that cannot run without
/// one. It is the one guard every use case that reads, queues or sends
/// something for the user goes through, and it fails, in this order, with:
///
/// - `notAuthenticated` when nobody is signed in;
/// - `sessionExpired` when the expiry has passed. The session is never
///   returned, and the caches are emptied (all of them, for every owner, as at
///   a sign-out): a session that ends while the app is running must not leave
///   the content of its user on the device. The purge is best effort, a failure
///   is captured and the caller still gets `sessionExpired`;
/// - `appLocked` when the session is valid but the app is locked (see
///   `AppLock`): until the biometric unlock succeeds, no use case returns data
///   to, or acts for, the user.
Future<Result<Session, SessionRequiredError>> requireSession(
  RequireSessionDeps deps,
) async {
  final Session? session;
  switch (await deps.auth.current()) {
    case Err(:final error):
      return err(error);
    case Ok(:final value):
      session = value;
  }
  if (session == null) {
    return err(notAuthenticated());
  }
  if (isSessionExpired(session, deps.clock.now())) {
    await purgeCaches(deps);
    return err(sessionExpired());
  }
  if (deps.appLock.isLocked()) {
    return err(appLocked());
  }
  return ok(session);
}

/// The same, and the user must be [expected]. A use case that started for a
/// user and has waited for something (the network, a biometric prompt) calls it
/// before it writes anything or returns anything: if somebody else is signed in
/// now, the answer is `sessionChanged` and the use case stops. The session it
/// returns is the one to read the identity from afterwards, not the one read
/// before the wait.
Future<Result<Session, AppError>> requireSameUser(
  RequireSessionDeps deps,
  UserId expected,
) async {
  switch (await requireSession(deps)) {
    case Err(:final error):
      return err(error);
    case Ok(:final value):
      if (value.user.id != expected) {
        return err(sessionChanged());
      }
      return ok(value);
  }
}
