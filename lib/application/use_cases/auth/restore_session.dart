import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/shared/purge_caches.dart';
import 'package:boardroom/application/shared/require_session.dart';
import 'package:boardroom/domain/entities/session.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/policies/session_expiry.dart';
import 'package:boardroom/domain/shared/constants.dart';
import 'package:boardroom/domain/shared/result.dart';

/// What [RestoreSession] needs: the session, the clock, both caches, the
/// monitoring and the lock shared by every use case (see `AppLock`). It is the
/// same set as the session guard needs.
typedef RestoreSessionDeps = RequireSessionDeps;

/// What a cold start found.
enum SessionRestore implements StableValue {
  /// Nobody is signed in: show the sign-in screen.
  none('none'),

  /// Somebody is signed in, but the app stays locked until they unlock it with
  /// the biometrics.
  unlockRequired('unlockRequired');

  new(this.value);

  @override
  final String value;
}

/// What a cold start found. A restored session always comes as
/// [SessionRestore.unlockRequired]: the app was closed, so nothing says how
/// long it has been away, and the biometric unlock is required every time. The
/// rule is part of the value, so that a screen cannot show the session without
/// having seen it. The presentation shows the lock screen and calls
/// `UnlockApp`.
///
/// The status is all it says. Who the user is (a name, an email) is not part of
/// it: nothing is disclosed before the unlock, and no screen can show it by
/// mistake.
typedef RestoredSession = ({SessionRestore status});

/// Finds out, on a cold start, whether somebody was signed in when the app was
/// last used. The app is locked first thing (see `AppLock`), and stays locked
/// until `UnlockApp` succeeds: a session that is restored gives no access to
/// anything before the biometrics.
///
/// Succeeds with `none` when nobody is signed in, and with `unlockRequired`
/// when somebody is. A stored session that has expired is ended: the caches are
/// emptied, the user is signed out, and the result is `none`. If emptying the
/// caches or signing out fails, the failure is captured and `none` is still
/// returned: an expired session is refused everywhere anyway.
///
/// On a device where the biometrics cannot be used (none enrolled, or removed
/// since), `UnlockApp` fails closed, every time: the app cannot be unlocked,
/// and the only way forward is to sign out and sign in again.
final class RestoreSession {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final RestoreSessionDeps _deps;

  /// Restores the session, if there is one.
  Future<Result<RestoredSession, StorageReadFailedError>> execute() async {
    final RestoreSessionDeps(:auth, :clock, :monitoring, :appLock) = _deps;

    appLock.lock();
    final Session? session;
    switch (await auth.current()) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        session = value;
    }

    if (session == null) {
      return ok((status: SessionRestore.none));
    }
    if (!isSessionExpired(session, clock.now())) {
      return ok((status: SessionRestore.unlockRequired));
    }

    monitoring.log(LogLevel.info, MonitoringEvent.sessionExpired);
    await purgeCaches(_deps);
    if (await auth.signOut() case Err(:final error)) {
      monitoring.captureError(MonitoringEvent.signOutFailed, error);
    }
    return ok((status: SessionRestore.none));
  }
}
