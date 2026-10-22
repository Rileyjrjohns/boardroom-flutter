part of 'app_error.dart';

/// The codes of the repository errors.
enum RepositoryErrorCode implements StableValue {
  /// The remote source could not be reached.
  networkUnavailable('networkUnavailable'),

  /// The remote source answered that the requested item does not exist.
  notFound('notFound'),

  /// The session is no longer valid.
  unauthorized('unauthorized'),

  /// The session is valid, but this user may not see this item.
  forbidden('forbidden'),

  /// Anything else: a server fault, an answer that cannot be read.
  unexpected('unexpected');

  new(this.value);

  @override
  final String value;
}

/// What a remote call can fail with when it addresses one item.
sealed class RepositoryError extends AppError {
  /// Creates a repository error.
  const new();
}

/// What a remote call can fail with when it addresses no particular item (a
/// listing): [NetworkUnavailableError], [UnauthorizedError] or
/// [UnexpectedError].
sealed class GatewayError extends RepositoryError {
  /// Creates a gateway error.
  const new();
}

/// The remote source could not be reached. The only error that the offline
/// policy recovers from.
final class NetworkUnavailableError extends GatewayError {
  /// Creates the error.
  const new();

  @override
  String get code => RepositoryErrorCode.networkUnavailable.value;
}

/// The remote source answered that the requested item does not exist.
final class NotFoundError extends RepositoryError {
  /// Creates the error.
  const new();

  @override
  String get code => RepositoryErrorCode.notFound.value;
}

/// The session is no longer valid: the remote source does not accept the
/// credentials of the caller (expired, revoked, signed out elsewhere). It
/// concerns everything the caller holds, not one item: the application empties
/// both caches. To be told apart from [ForbiddenError].
final class UnauthorizedError extends GatewayError {
  /// Creates the error.
  const new();

  @override
  String get code => RepositoryErrorCode.unauthorized.value;
}

/// The session is valid, but this user may not see this item (they were removed
/// from the meeting, the document is restricted). It concerns one item: the
/// application drops it, and what hangs off it, from the caches. A server that
/// prefers not to reveal that the item exists answers [NotFoundError] instead,
/// and the application treats the two the same way.
final class ForbiddenError extends RepositoryError {
  /// Creates the error.
  const new();

  @override
  String get code => RepositoryErrorCode.forbidden.value;
}

/// Anything else: a server fault, an answer that cannot be read. [cause] is a
/// technical diagnostic for the monitoring tools. It is never shown to the
/// user, and it is a status code and a kind of failure, nothing else: never a
/// file path, a URL, the location of a document or its title, a name, an email,
/// an id taken from a query, nor the choice of a vote.
final class UnexpectedError extends GatewayError {
  /// Creates the error, with a [cause] when there is one to report.
  const new({this.cause});

  /// The technical diagnostic, or null.
  final String? cause;

  @override
  String get code => RepositoryErrorCode.unexpected.value;

  @override
  Map<String, Object?> get payload =>
      cause == null ? const {} : {'cause': cause};
}

/// Builds a [NetworkUnavailableError].
NetworkUnavailableError networkUnavailable() => const NetworkUnavailableError();

/// Builds a [NotFoundError].
NotFoundError notFound() => const NotFoundError();

/// Builds an [UnauthorizedError].
UnauthorizedError unauthorized() => const UnauthorizedError();

/// Builds a [ForbiddenError].
ForbiddenError forbidden() => const ForbiddenError();

/// Builds an [UnexpectedError], with the technical [cause] when there is one.
UnexpectedError unexpected([String? cause]) => UnexpectedError(cause: cause);
