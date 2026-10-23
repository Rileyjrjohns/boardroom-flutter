import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/session/end_session.dart';

/// What [SignOut] needs: the session, both caches, the monitoring and the lock
/// shared by every use case (see `AppLock`).
typedef SignOutDeps = EndSessionDeps;

/// Signs the current user out, and empties the meeting and document caches
/// first (the stored content of the documents included), so that the next user
/// of the device finds nothing of what this one saw. Succeeds when nobody was
/// signed in. The app is locked first, and stays locked: the next sign-in opens
/// it again.
///
/// A cache that cannot be emptied is captured by the monitoring and does not
/// make the sign-out fail: the entries are kept per user (see `MeetingCache`),
/// so the next user cannot read them anyway, and the next sign-in empties the
/// caches again (see `SignIn`). The vote outbox is not touched: the votes of
/// this user wait for them to come back.
final class SignOut {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final SignOutDeps _deps;

  /// Signs the current user out.
  Future<Result<void, StorageWriteFailedError>> execute() =>
      closeSession(_deps);
}
