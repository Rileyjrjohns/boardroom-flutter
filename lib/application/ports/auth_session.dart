import 'package:boardroom/domain/entities/session.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/credentials.dart';

/// What can go wrong when signing in: [InvalidCredentialsError],
/// [NetworkUnavailableError], [UnexpectedError] or [StorageWriteFailedError].
typedef SignInFailure = AppError;

/// Signs the user in, remembers who is signed in, and signs them out. The
/// tokens that prove it stay inside the adapter (in the secure storage of the
/// device): the application only sees a [Session].
///
/// Contract: no method throws, and every method settles in bounded time (a
/// sign-in request that times out is `networkUnavailable`). The `cause` fields
/// of the errors must never hold personal data, a credential, a token, a path
/// or a URL.
///
/// `signIn` replaces any session that exists atomically: there is no instant at
/// which the adapter holds the tokens of two users, or none while a sign-in
/// succeeds. A refused sign-in leaves the current session as it was. Every
/// request the adapters of the remote ports make carries the identity that was
/// read when the request was created, never that of a user who signs in later.
///
/// `expiresAt` of a session is on the device clock (see [Session]): the
/// adapter computes it at sign-in from the `Clock` port and the lifetime the
/// server grants.
abstract interface class AuthSession {
  /// Checks the credentials and, when they are accepted, stores and returns the
  /// new session.
  Future<Result<Session, SignInFailure>> signIn(Credentials credentials);

  /// The stored session, or `null` when nobody is signed in. It is returned as
  /// stored, even when its expiry has passed: deciding that is the
  /// application's job, with the clock.
  Future<Result<Session?, StorageReadFailedError>> current();

  /// Forgets the session and its tokens. Signing out when nobody is signed in
  /// succeeds.
  Future<Result<void, StorageWriteFailedError>> signOut();
}
