import 'package:boardroom/application/ports/auth_session.dart';
import 'package:boardroom/application/shared/end_session.dart';
import 'package:boardroom/application/shared/purge_caches.dart';
import 'package:boardroom/domain/entities/session.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/credentials.dart';

/// What [SignIn] needs: the session, both caches, the monitoring and the lock
/// shared by every use case (see `AppLock`).
typedef SignInDeps = EndSessionDeps;

/// What [SignIn] fails with: a [ValidationError] or a [SignInFailure].
typedef SignInError = AppError;

/// Signs a user in with an email and a password. A badly formed email or an
/// empty password is a `validation` error: the server is not called.
///
/// Once the credentials are accepted, and before the new session is used by
/// anything, both caches are emptied: whoever signed in before (a sign-out that
/// never came, a session that expired while the app was closed, a purge that
/// failed) does not leave their content on the device for the new user. This is
/// also the retry of a purge that failed earlier. A purge that fails is
/// captured and does not stop the sign-in: the caches are kept per owner, so
/// the new user cannot read what is left, and the next sign-in tries again. The
/// app is locked while it is emptied and left unlocked after it: the user has
/// just typed their credentials, which is the proof of presence.
///
/// A refused sign-in changes nothing: the current session, the caches and the
/// lock stay as they were.
final class SignIn {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final SignInDeps _deps;

  /// Signs in with what the user typed, [email] and [password]. They are
  /// validated here, not by the screen.
  Future<Result<Session, SignInError>> execute({
    required String email,
    required String password,
  }) async {
    final SignInDeps(:auth, :appLock) = _deps;

    final signedIn = await andThenAsync<Credentials, Session, AppError>(
      createCredentials(email, password),
      auth.signIn,
    );
    if (signedIn case Err()) {
      return signedIn;
    }

    appLock.lock();
    await purgeCaches(_deps);
    appLock.unlock();
    return signedIn;
  }
}
