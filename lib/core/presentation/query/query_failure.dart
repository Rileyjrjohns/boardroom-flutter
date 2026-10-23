import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/errors/error_catalog.dart';

/// The failure of a use case, as Riverpod sees it: the error of the `Result`,
/// wrapped in a thrown value so that the provider goes to its error state.
///
/// THE CONVENTION for turning a `Result` into provider state. A use case
/// returns a `Result`; a query (an `AsyncNotifier` or a `FutureProvider`) must
/// either return data or throw. Throwing a [QueryFailure] keeps the machinery
/// of Riverpod honest: a failed refresh keeps the data of the last success
/// next to its error (`AsyncValue.hasValue` and `hasError` together), the
/// retry policy can read the code, and the screens read a typed `error`.
/// [unwrapResult] is the only place where a `Result` is thrown and
/// [QueryFailure] the only place it is recognised again. Actions (sign in,
/// vote, acknowledge) follow the same convention through `runResultAction`.
///
/// A failure can say which access it started under ([startedUnder], the epoch
/// of the session when the action began): one that ends the session is
/// applied only if that is still the current one, so that the refusal of an
/// action started by a user who has left does not end the session of the user
/// who came after.
final class QueryFailure implements Exception {
  /// Creates the failure of [error].
  const new(this.error, {this.startedUnder});

  /// What the use case answered.
  final AppError error;

  /// The epoch of the access the failing action started under, when known.
  final int? startedUnder;

  @override
  String toString() => 'QueryFailure(${error.code})';
}

/// The data of a success; a failure is thrown as a [QueryFailure].
T unwrapResult<T, E extends AppError>(
  Result<T, E> result, {
  int? startedUnder,
}) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => throw QueryFailure(error, startedUnder: startedUnder),
};

/// The code that says why something failed, from whatever was thrown. A use
/// case fails with a [QueryFailure], but nothing stops a bug from throwing
/// something else, and a screen must not crash on it: anything that is not
/// the failure of a use case, or whose code no screen has a text for, is
/// `unexpected`. The retry policy, the screens and the session end all go
/// through it.
String errorCodeOf(Object? error, ErrorCatalog catalog) {
  if (error is QueryFailure && catalog.has(error.error.code)) {
    return error.error.code;
  }
  return RepositoryErrorCode.unexpected.value;
}

/// The failures that say the user may not have this item, or that it is not
/// there: the screen of the item stops showing it, and so does the memory.
final Set<String> itemRefusalCodes = Set.unmodifiable({
  RepositoryErrorCode.forbidden.value,
  RepositoryErrorCode.notFound.value,
});
