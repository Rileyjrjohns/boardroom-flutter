import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/auth_session.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/value_objects/credentials.dart';
import 'package:boardroom/features/auth/domain/value_objects/email_address.dart';

import '../builders/builders.dart';

/// The password of the account every fake knows.
const String defaultPassword = 'secret';

/// Remembers one session, like the secure storage of the real adapter, and
/// signs in only the accounts the test registered: the credentials it is given
/// are compared with them, so a use case that changes the email or the password
/// on its way is caught. One account exists from the start
/// (`alice@example.com` and [defaultPassword], who is the default session).
/// Scriptable: a failure of the sign-in, and failures of the storage.
class FakeAuthSession implements AuthSession {
  /// The stored session; the default user is signed in. `null`: nobody is
  /// signed in.
  Session? session = aSession();

  /// Makes `signIn` fail with this error while set (no network, say), whatever
  /// the credentials.
  SignInFailure? signInFailure;

  /// Makes `current` fail while set.
  StorageReadFailedError? readFailure;

  /// Makes `signOut` fail while set (the session is kept).
  StorageWriteFailedError? signOutFailure;

  /// The credentials of every `signIn` call, in order.
  final List<Credentials> signInCalls = [];

  /// How many times `signOut` was called.
  int signOutCalls = 0;

  final Map<EmailAddress, ({String password, Session session})> _accounts = {
    anEmail(): (password: defaultPassword, session: aSession()),
  };

  /// An account that `signIn` accepts, and the session it opens.
  void registerAccount(EmailAddress email, String password, Session session) {
    _accounts[email] = (password: password, session: session);
  }

  @override
  Future<Result<Session, SignInFailure>> signIn(Credentials credentials) async {
    signInCalls.add(credentials);
    final failure = signInFailure;
    if (failure != null) {
      return err(failure);
    }

    final account = _accounts[credentials.email];
    if (account == null || account.password != credentials.password) {
      return err(invalidCredentials());
    }
    session = account.session;
    return ok(account.session);
  }

  @override
  Future<Result<Session?, StorageReadFailedError>> current() async {
    final failure = readFailure;
    if (failure != null) {
      return err(failure);
    }
    return ok(session);
  }

  @override
  Future<Result<void, StorageWriteFailedError>> signOut() async {
    signOutCalls += 1;
    final failure = signOutFailure;
    if (failure != null) {
      return err(failure);
    }
    session = null;
    return ok<void>(null);
  }
}
