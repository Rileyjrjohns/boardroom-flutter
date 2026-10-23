import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/infrastructure/http/protocol.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/domain/entities/user.dart';
import 'package:boardroom/features/auth/domain/value_objects/credentials.dart';
import 'package:boardroom/features/auth/domain/value_objects/email_address.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

part 'session_dto.g.dart';

// Signing in: `POST /auth/sign-in`.

const int _millisPerSecond = 1000;

/// What a token is made of: visible ASCII, no space, no control character. It
/// goes into the `Authorization` header, where anything else is at best refused
/// and at worst the means to add a header of one's own.
final RegExp _tokenFormat = RegExp(r'^[\x21-\x7E]+$');

/// Far longer than any token, short enough that a hostile answer cannot fill
/// the keychain.
const int _maxTokenLength = 4096;

/// The longest session the app accepts: a server that grants more is wrong, or
/// hostile.
const int maxSessionLifetimeSeconds = 30 * 24 * 60 * 60;

const String _invalidToken = 'not a token';
const String _invalidTokenType = 'not a bearer token';
const String _invalidLifetime = 'not a session lifetime';

String _readAccessToken(Object raw) {
  if (raw is! String ||
      raw.isEmpty ||
      raw.length > _maxTokenLength ||
      !_tokenFormat.hasMatch(raw)) {
    throw const FormatException(_invalidToken);
  }
  return raw;
}

String _readTokenType(Object raw) {
  if (raw != bearerTokenType) {
    throw const FormatException(_invalidTokenType);
  }
  return bearerTokenType;
}

num _readLifetime(Object raw) {
  if (raw is! num || raw > maxSessionLifetimeSeconds) {
    throw const FormatException(_invalidLifetime);
  }
  return raw;
}

/// A user of the API: the `user` of a sign-in answer, an account of the
/// fixtures.
@JsonSerializable(checked: true)
final class UserWire {
  /// Creates the wire form of a user.
  const new({required this.id, required this.fullName, required this.email});

  /// Reads the wire form of a user, or throws a `CheckedFromJsonException` at
  /// the first field that is missing or has the wrong type.
  factory fromJson(Map<String, dynamic> json) => _$UserWireFromJson(json);

  /// The identifier of the user.
  final String id;

  /// The full name of the user.
  final String fullName;

  /// The email address of the user.
  final String email;

  /// The JSON object of this user.
  Map<String, dynamic> toJson() => _$UserWireToJson(this);
}

/// The body of `POST /auth/sign-in`.
@JsonSerializable(checked: true)
final class SignInRequestWire {
  /// Creates the wire form of a sign-in request.
  const new({required this.email, required this.password});

  /// Reads a sign-in request, or throws a `CheckedFromJsonException` at the
  /// first field that is missing or has the wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$SignInRequestWireFromJson(json);

  /// The email address, as typed.
  final String email;

  /// The password, as typed.
  final String password;

  /// The JSON object of this request.
  Map<String, dynamic> toJson() => _$SignInRequestWireToJson(this);

  // The password is a secret: it never appears in a log.
  @override
  String toString() => 'SignInRequestWire(email: $email)';
}

/// The answer to `POST /auth/sign-in`.
@JsonSerializable(checked: true, explicitToJson: true)
final class SignInResponseWire {
  /// Creates the wire form of a sign-in answer.
  const new({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
  });

  /// Reads a sign-in answer, or throws a `CheckedFromJsonException` at the
  /// first field that is missing or has the wrong type, or that no token or
  /// lifetime the app accepts can be.
  factory fromJson(Map<String, dynamic> json) =>
      _$SignInResponseWireFromJson(json);

  /// The token: visible ASCII, no space, at most 4096 characters.
  @JsonKey(fromJson: _readAccessToken)
  final String accessToken;

  /// The kind of token: always `Bearer`.
  @JsonKey(fromJson: _readTokenType)
  final String tokenType;

  /// How long the token lasts, in seconds, from the moment it is issued: at
  /// most [maxSessionLifetimeSeconds]. A lifetime of zero is a session that is
  /// already over.
  @JsonKey(fromJson: _readLifetime)
  final num expiresIn;

  /// The user the token was issued to.
  final UserWire user;

  /// The JSON object of this answer.
  Map<String, dynamic> toJson() => _$SignInResponseWireToJson(this);

  // The token is a secret: it never appears in a log.
  @override
  String toString() => 'SignInResponseWire(user: ${user.id})';
}

/// The token, which stays inside the adapter, and the session, which is all the
/// app sees.
@immutable
final class SignedIn {
  /// Creates a sign-in outcome.
  const new({required this.token, required this.session});

  /// The bearer token.
  final String token;

  /// The session the server granted.
  final Session session;

  @override
  bool operator ==(Object other) =>
      other is SignedIn && other.token == token && other.session == session;

  @override
  int get hashCode => Object.hash(token, session);

  // The token is a secret: it never appears in a log.
  @override
  String toString() => 'SignedIn(session: $session)';
}

/// The user of the API (a sign-in answer, an account of the fixtures), through
/// the factories of the domain.
Result<User, ValidationError> toUser(UserWire wire) => andThen(
  parseUserId(wire.id),
  (id) => andThen(
    parseEmailAddress(wire.email),
    (email) => createUser(id: id, fullName: wire.fullName, email: email),
  ),
);

/// The session the server granted. The expiry is computed on the clock of the
/// device from the lifetime the server grants (see `AuthSession`), never copied
/// from a timestamp of the server.
Result<SignedIn, ValidationError> toSignedIn(
  SignInResponseWire wire,
  Instant now,
) => andThen(
  toUser(wire.user),
  (user) => andThen(
    durationFromMillis(wire.expiresIn * _millisPerSecond),
    (lifetime) => andThen(
      plus(now, lifetime),
      (expiresAt) => ok(
        SignedIn(
          token: wire.accessToken,
          session: createSession(user: user, expiresAt: expiresAt),
        ),
      ),
    ),
  ),
);

/// The credentials, written as the API reads them: as typed.
SignInRequestWire toSignInRequestWire(Credentials credentials) =>
    SignInRequestWire(email: credentials.email, password: credentials.password);

/// A sign-in outcome written as the API answers it, for the simulated server.
SignInResponseWire toSignInResponseWire(
  SignedIn signedIn,
  int lifetimeSeconds,
) {
  final user = signedIn.session.user;
  return SignInResponseWire(
    accessToken: signedIn.token,
    tokenType: bearerTokenType,
    expiresIn: lifetimeSeconds,
    user: UserWire(id: user.id, fullName: user.fullName, email: user.email),
  );
}
