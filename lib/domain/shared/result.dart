import 'dart:async';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// The outcome of an operation that can fail. Every fallible operation of the
/// domain and of the application returns a `Result` (or a `Future<Result>`): no
/// exception crosses a layer. The error side is plain data, never a thrown
/// value and never a user-facing text.
///
/// A `Result` is either an [Ok] or an [Err]; `switch` over it is exhaustive:
///
/// ```dart
/// switch (result) {
///   case Ok(:final value): ...
///   case Err(:final error): ...
/// }
/// ```
///
/// Build one with [ok] and [err] only. Their types (`Ok<T, Never>` and
/// `Err<Never, E>`) make a success assignable to any `Result<T, E>` and a
/// failure to any `Result<T, E>`, as the covariance of Dart generics allows.
@immutable
sealed class Result<T, E> {
  const new();
}

/// A success holding a [value]. Built by [ok].
@immutable
final class Ok<T, E> extends Result<T, E> {
  const new _(this.value);

  /// What the operation produced.
  final T value;

  @override
  bool operator ==(Object other) =>
      other is Ok<Object?, Object?> &&
      const DeepCollectionEquality().equals(value, other.value);

  @override
  int get hashCode =>
      Object.hash(Ok, const DeepCollectionEquality().hash(value));

  @override
  String toString() => 'Ok($value)';
}

/// A failure holding an [error]. Built by [err].
@immutable
final class Err<T, E> extends Result<T, E> {
  const new _(this.error);

  /// Why the operation failed.
  final E error;

  @override
  bool operator ==(Object other) =>
      other is Err<Object?, Object?> &&
      const DeepCollectionEquality().equals(error, other.error);

  @override
  int get hashCode =>
      Object.hash(Err, const DeepCollectionEquality().hash(error));

  @override
  String toString() => 'Err($error)';
}

/// A success. A `Result<void, E>` succeeds with `ok<void>(null)`.
Ok<T, Never> ok<T>(T value) => Ok<T, Never>._(value);

/// A failure.
Err<Never, E> err<E>(E error) => Err<Never, E>._(error);

/// Whether [result] is a success.
bool isOk<T, E>(Result<T, E> result) => result is Ok<T, E>;

/// Whether [result] is a failure.
bool isErr<T, E>(Result<T, E> result) => result is Err<T, E>;

/// Transforms the value of a success; a failure is returned as is.
Result<U, E> map<T, U, E>(
  Result<T, E> result,
  U Function(T value) transform,
) => switch (result) {
  Ok(:final value) => ok(transform(value)),
  // An Err is only built by err(), so it is an Err<Never, E>: it is already a
  // Result<U, E>.
  Err() => result as Result<U, E>,
};

/// Chains a step that can fail on a success; a failure short-circuits and is
/// returned as is. When the two steps fail with different errors, `E` is their
/// closest common type (`AppError` for the errors of the domain).
Result<U, E> andThen<T, U, E>(
  Result<T, E> result,
  Result<U, E> Function(T value) next,
) => switch (result) {
  Ok(:final value) => next(value),
  Err() => result as Result<U, E>,
};

/// [andThen] for an asynchronous step. It also accepts the future of the first
/// result, so that a port call can be chained without an intermediate `await`
/// and `if`:
///
/// ```dart
/// andThenAsync(gate.checkAvailability(), (_) => gate.authenticate(reason))
/// ```
Future<Result<U, E>> andThenAsync<T, U, E>(
  FutureOr<Result<T, E>> result,
  Future<Result<U, E>> Function(T value) next,
) async {
  final settled = await result;
  return switch (settled) {
    Ok(:final value) => await next(value),
    Err() => settled as Result<U, E>,
  };
}
