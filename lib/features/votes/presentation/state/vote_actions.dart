import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/presentation/query/result_action.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/use_cases/cast_vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/presentation/providers.dart';
import 'package:boardroom/features/votes/presentation/state/pending_votes.dart';
import 'package:boardroom/features/votes/presentation/state/refresh_meetings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'vote_actions.g.dart';

/// Casts a vote on one resolution: the `CastVote` use case, which asks for the
/// biometric confirmation. Once it has succeeded, the queries that show the
/// vote are asked again, and `onCast` is called when they have answered, so the
/// screen that closes its confirmation at that moment shows the vote where it
/// is:
///
/// - submitted: the server recorded it, so the meeting is asked again (the
///   resolution carries the vote) and so is the outbox (nothing changed there,
///   but a rejected vote of an earlier attempt may have);
/// - queued: it waits in the outbox, and that is what changed.
///
/// A vote the rules refuse tells the screen something new about the meeting (it
/// closed, the user voted elsewhere), so those refreshes happen for a refusal
/// too. Nothing is shown before the use cases have answered: there is no
/// optimistic vote.
@riverpod
class CastVoteAction extends _$CastVoteAction {
  @override
  ActionState build(ResolutionId resolutionId) => const ActionState.idle();

  /// Casts [choice] on this resolution of [meetingId].
  Future<void> run({
    required MeetingId meetingId,
    required VoteChoice choice,
    required void Function(CastVoteOutcome outcome) onCast,
  }) => runResultAction<CastVoteOutcome>(
    ref: ref,
    current: () => state,
    emit: (next) => state = next,
    execute: () => ref
        .read(castVoteUseCaseProvider)
        .execute(
          meetingId: meetingId,
          resolutionId: resolutionId,
          choice: choice,
        ),
    onSuccess: (outcome, _) async {
      await Future.wait([
        if (outcome.status == CastVoteStatus.submitted)
          refreshMeeting(ref, meetingId),
        refreshPendingVotes(ref),
      ]);
      onCast(outcome);
    },
    onFailure: (failure, _) async {
      final learnedSomething =
          isVotingError(failure) ||
          failure.code == VoteDeliveryErrorCode.previouslyRejected.value;
      if (learnedSomething) {
        await Future.wait([
          refreshMeeting(ref, meetingId),
          refreshPendingVotes(ref),
        ]);
      }
    },
  );

  /// Forgets the last failure.
  void reset() => state = const ActionState.idle();
}

/// Acknowledges a rejected vote: the use case deletes it from the outbox, and
/// the outbox is asked again, which lets the user vote again on the resolution
/// when the rules still allow it.
@riverpod
class AcknowledgeRejectedVoteAction extends _$AcknowledgeRejectedVoteAction {
  @override
  ActionState build(ResolutionId resolutionId) => const ActionState.idle();

  /// Acknowledges the rejected vote of this resolution.
  Future<void> run() => runResultAction<void>(
    ref: ref,
    current: () => state,
    emit: (next) => state = next,
    execute: () => ref
        .read(acknowledgeRejectedVoteUseCaseProvider)
        .execute(resolutionId: resolutionId),
    onSuccess: (_, _) => refreshPendingVotes(ref),
  );
}

/// Discards the entries of the outbox that can no longer be read as a vote, on
/// the user's request. The outbox is asked again afterwards, which makes the
/// notice that told the user about them go.
@riverpod
class DiscardUnreadableVotesAction extends _$DiscardUnreadableVotesAction {
  @override
  ActionState build() => const ActionState.idle();

  /// Deletes what cannot be read.
  Future<void> run() => runResultAction<int>(
    ref: ref,
    current: () => state,
    emit: (next) => state = next,
    execute: () => ref.read(discardUnreadableVotesUseCaseProvider).execute(),
    onSuccess: (_, _) => refreshPendingVotes(ref),
  );

  /// Forgets the last failure.
  void reset() => state = const ActionState.idle();
}
