import 'dart:async';

import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/query/query_failure.dart';
import 'package:boardroom/core/presentation/query/query_lifetime.dart';
import 'package:boardroom/features/auth/domain/entities/user.dart';
import 'package:boardroom/features/auth/presentation/providers.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/votes/application/use_cases/list_pending_votes.dart';
import 'package:boardroom/features/votes/presentation/providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pending_votes.g.dart';

/// The votes of the signed-in user in the outbox: the ones waiting to be sent
/// and the rejected ones. It is server state like any other, even though it is
/// read from the device: it changes when a vote is cast, when a synchronisation
/// runs and when a rejected vote is acknowledged, and each of those refreshes
/// this provider (see `refreshPendingVotes`). It does not run while the app is
/// not open.
@riverpod
Future<OutboxContent> pendingVotes(Ref ref) async {
  ref.keepQueryFor();
  // The access this answer is for; the query itself is dropped when it moves
  // (see `keepQueryFor`).
  final epoch = ref.read(sessionEpochProvider);
  if (!ref.read(sessionOpenProvider)) {
    // Nothing of the user is read outside the open app: the provider is read
    // again when the app opens.
    return await Completer<OutboxContent>().future;
  }
  final result = await ref.read(listPendingVotesUseCaseProvider).execute();
  final OutboxContent content = unwrapResult(result, startedUnder: epoch);
  return content;
}

/// Who the signed-in user is, for the eligibility rule of the votes. It is
/// shared by every resolution of every meeting.
@riverpod
Future<User> voter(Ref ref) async {
  ref.keepQueryFor();
  // The access this answer is for; the query itself is dropped when it moves
  // (see `keepQueryFor`).
  final epoch = ref.read(sessionEpochProvider);
  if (!ref.read(sessionOpenProvider)) {
    return await Completer<User>().future;
  }
  final result = await ref.read(getCurrentUserUseCaseProvider).execute();
  final User user = unwrapResult(result, startedUnder: epoch);
  return user;
}

/// Reads the outbox again and settles when it has answered, so that a button
/// stays busy until the screen shows the outcome. A failure is left to the
/// screen that reads the provider.
Future<void> refreshPendingVotes(Ref ref) async {
  ref.invalidate(pendingVotesProvider);
  try {
    await ref.read(pendingVotesProvider.future);
  } on Object {
    // Told by the provider to whoever shows it.
  }
}
