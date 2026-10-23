import 'package:boardroom/application/ports/auth_session.dart';
import 'package:boardroom/application/ports/clock.dart';
import 'package:boardroom/domain/entities/session.dart';
import 'package:boardroom/domain/entities/user.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/credentials.dart';
import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/infrastructure/in_memory/simulated_network.dart';
import 'package:meta/meta.dart';

/// An account the simulated server knows. The password is a demo value, not a
/// secret.
@immutable
final class DemoAccount {
  /// Creates the account of [user].
  const new({required this.user, required this.password});

  /// Who the account is.
  final User user;

  /// The demo password.
  final String password;

  @override
  bool operator ==(Object other) =>
      other is DemoAccount && other.user == user && other.password == password;

  @override
  int get hashCode => Object.hash(user, password);

  // Not a secret, but not something to print either.
  @override
  String toString() => 'DemoAccount(user: ${user.id})';
}

/// Authentication against the accounts of the simulated server, and the session
/// store of the device in one: it checks the credentials like the server would,
/// and remembers who is signed in like the secure storage would. Tokens do not
/// exist here, so none can leak.
///
/// A session expires `sessionLifetime` after the sign-in, on the clock it is
/// given. `current` returns it as stored, expired or not, as the port requires.
final class InMemoryAuthSession implements AuthSession {
  /// Creates the store. [clock] is what sessions expire on. Signing in is a
  /// request to the server: it goes through the same [network] as the others.
  /// [accounts] are the ones the server knows, and [sessionLifetime] how long a
  /// session lasts, counted on the device clock from the sign-in.
  new({
    required this.clock,
    required this.network,
    required this.accounts,
    required this.sessionLifetime,
  });

  /// The clock a session expires on.
  final Clock clock;

  /// The network the sign-in goes through.
  final SimulatedNetwork network;

  /// The accounts of the simulated server.
  final List<DemoAccount> accounts;

  /// How long a session lasts.
  final DurationMillis sessionLifetime;

  Session? _session;

  /// Opens a session for a user without asking for credentials. For the mock
  /// configuration that starts signed in, and for tests. Fails only when the
  /// expiry would leave the range of an instant.
  Result<Session, ValidationError> openSessionFor(User user) {
    switch (plus(clock.now(), sessionLifetime)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        final session = createSession(user: user, expiresAt: value);
        _session = session;
        return ok(session);
    }
  }

  @override
  Future<Result<Session, SignInFailure>> signIn(Credentials credentials) async {
    final reached = await network.enter();
    if (reached case Err(:final error)) {
      return err(error);
    }
    DemoAccount? account;
    for (final candidate in accounts) {
      if (candidate.user.email == credentials.email) {
        account = candidate;
        break;
      }
    }
    if (account == null || account.password != credentials.password) {
      return err(invalidCredentials());
    }
    switch (openSessionFor(account.user)) {
      case Ok(:final value):
        return ok(value);
      case Err():
        return err(unexpected());
    }
  }

  @override
  Future<Result<Session?, StorageReadFailedError>> current() async =>
      ok(_session);

  @override
  Future<Result<void, StorageWriteFailedError>> signOut() async {
    _session = null;
    return ok<void>(null);
  }
}
