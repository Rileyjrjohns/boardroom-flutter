import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/auth/application/ports/auth_session.dart';
import 'package:boardroom/features/auth/application/session/app_lock.dart';
import 'package:boardroom/features/auth/application/session/purge_caches.dart';

/// What [closeSession] and [endRefusedSession] need, on top of what
/// [purgeCaches] needs.
abstract interface class EndSessionDeps implements PurgeCachesDeps {
  /// The stored session.
  AuthSession get auth;

  /// The instance shared by every use case: see [AppLock].
  AppLock get appLock;
}

/// Ends the session on the device: the app is locked, both caches are emptied,
/// and the session is forgotten. It is what signing out is (see `SignOut`), and
/// the part of it that a session the server refused shares.
Future<Result<void, StorageWriteFailedError>> closeSession(
  EndSessionDeps deps,
) async {
  deps.appLock.lock();
  await purgeCaches(deps);
  return await deps.auth.signOut();
}

/// The server said the token of [user] is no longer valid (`unauthorized`): the
/// session is over, whatever the user was doing, and the device must not go on
/// as if it were not. So the session is ended here, once, by the application
/// layer that met the answer (the single place is this function; the cache
/// fallback, the vote and the synchronisation all call it): the app is locked,
/// the caches are emptied and the session is forgotten, so that a restart does
/// not restore a session the server refused and nothing is sent with it again.
/// The votes in the outbox stay: they wait for the user to come back.
///
/// It never fails, since the caller has the refusal to report: a session that
/// cannot be forgotten is captured (`signOutFailed`) and the caller still gets
/// `unauthorized`. The interface then sends the user to the sign-in screen, and
/// does not sign out a second time for this code.
///
/// Only the session of [user] is ended. `unauthorized` is also what an adapter
/// answers when the token it holds is not the one of the user the request was
/// made for (somebody signed in while it was on its way): the session now open
/// is another one, and it was not refused. Nothing is touched then, and nothing
/// is touched either when nobody is signed in any more.
Future<void> endRefusedSession(EndSessionDeps deps, UserId user) async {
  final current = await deps.auth.current();
  // A session that cannot be read cannot be told from the refused one: it is
  // ended, like it.
  if (current case Ok(:final value) when value?.user.id != user) {
    return;
  }

  final closed = await closeSession(deps);
  if (closed case Err(:final error)) {
    deps.monitoring.captureError(MonitoringEvent.signOutFailed, error, {
      LogAttribute.userId: user,
    });
  }
}
