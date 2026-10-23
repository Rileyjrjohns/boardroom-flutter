import 'package:boardroom/features/votes/application/use_cases/acknowledge_rejected_vote.dart';
import 'package:boardroom/features/votes/application/use_cases/cast_vote.dart';
import 'package:boardroom/features/votes/application/use_cases/discard_unreadable_votes.dart';
import 'package:boardroom/features/votes/application/use_cases/list_pending_votes.dart';
import 'package:boardroom/features/votes/application/use_cases/sync_pending_votes.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'providers.g.dart';

// What the screens of the votes need from the outside. They throw until
// `lib/app/providers` overrides them in the root `ProviderScope` (a widget test
// overrides them with use cases over fakes).

/// Casts a vote (after the biometric confirmation), or queues it offline.
@Riverpod(keepAlive: true)
CastVote castVoteUseCase(Ref ref) =>
    throw UnimplementedError('castVoteUseCaseProvider');

/// Sends the votes that wait in the outbox.
@Riverpod(keepAlive: true)
SyncPendingVotes syncPendingVotesUseCase(Ref ref) =>
    throw UnimplementedError('syncPendingVotesUseCaseProvider');

/// Lists the votes that are not settled.
@Riverpod(keepAlive: true)
ListPendingVotes listPendingVotesUseCase(Ref ref) =>
    throw UnimplementedError('listPendingVotesUseCaseProvider');

/// Removes a rejected vote from the list once the user has read it.
@Riverpod(keepAlive: true)
AcknowledgeRejectedVote acknowledgeRejectedVoteUseCase(Ref ref) =>
    throw UnimplementedError('acknowledgeRejectedVoteUseCaseProvider');

/// Deletes the saved votes that can no longer be read.
@Riverpod(keepAlive: true)
DiscardUnreadableVotes discardUnreadableVotesUseCase(Ref ref) =>
    throw UnimplementedError('discardUnreadableVotesUseCaseProvider');
