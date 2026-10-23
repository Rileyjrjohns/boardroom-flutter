// The authentication errors: who the user is and whether the app is open to
// them. They extend the open `AppError` of the core, and the family is sealed
// here, in the feature that owns it.

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';

/// The codes of the authentication errors.
enum AuthenticationErrorCode implements StableValue {
  /// The email and password pair was refused.
  invalidCredentials('invalidCredentials'),

  /// A session exists but its expiry has passed.
  sessionExpired('sessionExpired'),

  /// An operation that needs a signed-in user ran without a session.
  notAuthenticated('notAuthenticated'),

  /// The user who started a long operation is no longer the signed-in user.
  sessionChanged('sessionChanged'),

  /// The session is valid but the app is locked.
  appLocked('appLocked');

  new(this.value);

  @override
  final String value;
}

/// What can go wrong with who the user is. The family is sealed in this
/// library, so a `switch` over it is checked to be exhaustive.
sealed class AuthenticationError extends AppError {
  /// Creates an authentication error.
  const new();
}

/// The email and password pair was refused.
final class InvalidCredentialsError extends AuthenticationError {
  /// Creates the error.
  const new();

  @override
  String get code => AuthenticationErrorCode.invalidCredentials.value;
}

/// A session exists but its expiry has passed.
final class SessionExpiredError extends AuthenticationError {
  /// Creates the error.
  const new();

  @override
  String get code => AuthenticationErrorCode.sessionExpired.value;
}

/// An operation that needs a signed-in user ran without a session.
final class NotAuthenticatedError extends AuthenticationError {
  /// Creates the error.
  const new();

  @override
  String get code => AuthenticationErrorCode.notAuthenticated.value;
}

/// The user who started a long operation is no longer the signed-in user.
final class SessionChangedError extends AuthenticationError {
  /// Creates the error.
  const new();

  @override
  String get code => AuthenticationErrorCode.sessionChanged.value;
}

/// A session exists and is valid, but the app is locked: nobody has proven they
/// are there since the app was started, or since it came back from the
/// background past the grace period. Nothing is read, queued or sent for the
/// user until the biometric unlock succeeds.
final class AppLockedError extends AuthenticationError {
  /// Creates the error.
  const new();

  @override
  String get code => AuthenticationErrorCode.appLocked.value;
}

/// Builds an [InvalidCredentialsError].
InvalidCredentialsError invalidCredentials() => const InvalidCredentialsError();

/// Builds a [SessionExpiredError].
SessionExpiredError sessionExpired() => const SessionExpiredError();

/// Builds a [NotAuthenticatedError].
NotAuthenticatedError notAuthenticated() => const NotAuthenticatedError();

/// Builds a [SessionChangedError].
SessionChangedError sessionChanged() => const SessionChangedError();

/// Builds an [AppLockedError].
AppLockedError appLocked() => const AppLockedError();
