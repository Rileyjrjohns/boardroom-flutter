import 'dart:async';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// Where an action of the user stands (sign in, unlock, sign out, cast a vote,
/// acknowledge a rejected vote): nothing yet, under way, or failed with an
/// error. It is the state of the notifier of the action.
@immutable
final class ActionState {
  const new _(this.isPending, this.failure);

  /// Nothing has been done, or the last failure was forgotten.
  const new idle() : this._(false, null);

  /// The use case is under way.
  const new pending() : this._(true, null);

  /// The use case answered with [failure].
  const new failed(AppError failure) : this._(false, failure);

  /// Whether the use case is under way: the button is busy.
  final bool isPending;

  /// Why the last run failed, typed by the code. Null otherwise.
  final AppError? failure;

  @override
  bool operator ==(Object other) =>
      other is ActionState &&
      other.isPending == isPending &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(isPending, failure);
}

/// THE CONVENTION for an action of the user. It is the mutation counterpart of
/// `unwrapResult` (the `useResultMutation` of the React Native app):
///
/// - [execute] calls a use case, never an adapter;
/// - it is never retried, whatever the error: an action is repeated by the
///   user, not by the machinery;
/// - a second call while one is under way is ignored (`current().isPending`),
///   so a double tap acts once even before the screen has rebuilt;
/// - [onSuccess] runs when the use case succeeded and the action stays
///   pending until it settles: a screen that refreshes what the action changed
///   keeps its button busy until the refresh is done. Nothing is optimistic;
/// - [onFailure] runs when the use case failed, for what the failure leaves
///   stale. Both are told the epoch of the access the action started under;
/// - a failure that ends the session ends it through
///   `sessionEndHandlerProvider`, for the epoch it started under only;
/// - nothing is written once the notifier is gone.
///
/// The notifier passes its own `ref`, `state` getter and setter:
///
/// ```dart
/// Future<void> run() => runResultAction<void>(
///   ref: ref,
///   current: () => state,
///   emit: (next) => state = next,
///   execute: () => ref.read(signOutUseCaseProvider).execute(),
/// );
/// ```
Future<void> runResultAction<O>({
  required Ref ref,
  required ActionState Function() current,
  required void Function(ActionState next) emit,
  required Future<Result<O, AppError>> Function() execute,
  FutureOr<void> Function(O output, int startedUnder)? onSuccess,
  FutureOr<void> Function(AppError failure, int startedUnder)? onFailure,
}) async {
  if (current().isPending) {
    return;
  }
  final startedUnder = ref.read(sessionEpochProvider);
  emit(const ActionState.pending());

  Result<O, AppError> result;
  try {
    result = await execute();
  } on Object {
    result = err(const UnexpectedError());
  }
  if (!ref.mounted) {
    return;
  }

  switch (result) {
    case Ok(:final value):
      await onSuccess?.call(value, startedUnder);
      if (ref.mounted) {
        emit(const ActionState.idle());
      }
    case Err(:final error):
      ref.read(sessionEndHandlerProvider)(error.code, startedUnder);
      if (ref.mounted) {
        emit(ActionState.failed(error));
        await onFailure?.call(error, startedUnder);
      }
  }
}
