import 'package:boardroom/application/ports/auth_session.dart';
import 'package:boardroom/application/ports/clock.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/entities/session.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/credentials.dart';
import 'package:boardroom/infrastructure/http/dto/session_dto.dart';
import 'package:boardroom/infrastructure/http/dto/wire.dart';
import 'package:boardroom/infrastructure/http/http_client.dart';
import 'package:boardroom/infrastructure/http/invalid_response.dart';
import 'package:boardroom/infrastructure/http/protocol.dart';
import 'package:boardroom/infrastructure/http/status_cause.dart';
import 'package:boardroom/infrastructure/secure_storage/session_vault.dart';
import 'package:meta/meta.dart';

/// What `HttpAuthSession` is made of.
@immutable
final class HttpAuthSessionOptions {
  /// Creates the options.
  const new({
    required this.client,
    required this.vault,
    required this.clock,
    required this.monitoring,
  });

  /// The client that talks to the API.
  final HttpClient client;

  /// Where the session and its token are kept, and where the client reads the
  /// token from.
  final SessionVault vault;

  /// The clock the expiry of a session is computed on.
  final Clock clock;

  /// Where the answers that do not have the shape of the API are reported.
  final Monitoring monitoring;
}

/// Authentication against the API (`POST /auth/sign-in`), with the session kept
/// in the secure storage of the device (`SessionVault`).
///
/// - The server answers with a token and the lifetime it grants. The token
///   stays in the vault: the application only ever sees the `Session`, whose
///   expiry is computed here, on the clock of the device, from that lifetime.
/// - A new session replaces the old one with one write; a refused sign-in
///   changes nothing.
/// - `current` reads the session from memory once it has been loaded from the
///   storage.
/// - Signing out forgets the session on the device. The demo API has no
///   endpoint to revoke a token: it stays valid on the server until it expires
///   (see docs/api.md).
final class HttpAuthSession implements AuthSession {
  /// Creates the session of a device.
  const new(this._options);

  final HttpAuthSessionOptions _options;

  @override
  Future<Result<Session, SignInFailure>> signIn(Credentials credentials) async {
    final HttpAuthSessionOptions(:client, :vault, :clock, :monitoring) =
        _options;

    final answer = await client.request(
      () => HttpRequestSpec<SignInResponseWire>(
        method: HttpMethod.post,
        path: Routes.signIn,
        body: toSignInRequestWire(credentials).toJson(),
        authenticated: false,
        resource: HttpResource.session,
        decode: (json) => decodeWire(json, SignInResponseWire.fromJson),
      ),
    );
    final SignInResponseWire wire;
    switch (answer) {
      case Err(:final error):
        return err(_signInFailureOf(error));
      case Ok(:final value):
        wire = value;
    }

    final SignedIn signedIn;
    switch (toSignedIn(wire, clock.now())) {
      case Err(:final error):
        return err(domainViolation(monitoring, HttpResource.session, error));
      case Ok(:final value):
        signedIn = value;
    }

    final stored = await vault.replace(signedIn);
    switch (stored) {
      case Ok():
        return ok(signedIn.session);
      case Err(:final error):
        return err(error);
    }
  }

  @override
  Future<Result<Session?, StorageReadFailedError>> current() =>
      _options.vault.session();

  @override
  Future<Result<void, StorageWriteFailedError>> signOut() =>
      _options.vault.clear();
}

/// 401 is the server refusing the credentials: signing in has no session to
/// end.
SignInFailure _signInFailureOf(HttpFailure failure) => switch (failure) {
  RequestFailed(:final error) => switch (error) {
    UnauthorizedError() => invalidCredentials(),
    NetworkUnavailableError() || UnexpectedError() => error,
    ForbiddenError() => unexpected(statusCause(HttpStatusCode.forbidden.code)),
    NotFoundError() => unexpected(statusCause(HttpStatusCode.notFound.code)),
  },
  RequestRejected() => unexpected(
    statusCause(HttpStatusCode.unprocessableContent.code),
  ),
};
