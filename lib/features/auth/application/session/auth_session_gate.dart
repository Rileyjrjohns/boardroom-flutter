import 'package:boardroom/core/application/ports/session_gate.dart';
import 'package:boardroom/core/application/ports/types/session_refusal.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/auth/application/session/end_session.dart'
    as session;
import 'package:boardroom/features/auth/application/session/purge_caches.dart';
import 'package:boardroom/features/auth/application/session/require_session.dart'
    as session;
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';

/// The session gate of the offline policy, over the session guards of `auth`:
/// the answers of `requireSameUser` and `endRefusedSession`, in the terms of
/// `core` (a user id and a [SessionRefusal]).
final class AuthSessionGate implements SessionGate {
  /// Creates the gate over [_deps].
  const new(this._deps);

  final session.RequireSessionDeps _deps;

  @override
  Future<Result<UserId, SessionRefusal>> requireSameUser(
    UserId expected,
  ) async {
    switch (await session.requireSameUser(_deps, expected)) {
      case Ok(:final value):
        return ok(value.user.id);
      case Err(:final error):
        return err(
          SessionRefusal(
            error: error,
            sessionKept: error.code == AuthenticationErrorCode.appLocked.value,
          ),
        );
    }
  }

  @override
  Future<void> endRefusedSession(UserId user) =>
      session.endRefusedSession(_deps, user);

  @override
  Future<void> purgeSessionData() => purgeCaches(_deps);
}
