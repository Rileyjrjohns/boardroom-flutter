import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/session/require_session.dart';
import 'package:boardroom/features/auth/domain/entities/user.dart';

/// What [GetCurrentUser] needs: what the session guard needs.
typedef GetCurrentUserDeps = RequireSessionDeps;

/// What [GetCurrentUser] fails with: the errors of the session guard.
typedef GetCurrentUserError = SessionRequiredError;

/// Who is signed in, for a screen that applies a rule to the user (may this
/// user vote on that resolution?). It goes through the session guard like every
/// use case that serves the user, so nothing is disclosed before the unlock:
/// `RestoreSession` says that somebody is signed in and nothing about who, and
/// this answers `appLocked` until the biometrics succeed.
final class GetCurrentUser {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final GetCurrentUserDeps _deps;

  /// The signed-in user.
  Future<Result<User, GetCurrentUserError>> execute() async {
    switch (await requireSession(_deps)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        return ok(value.user);
    }
  }
}
