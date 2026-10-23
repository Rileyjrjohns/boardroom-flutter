import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/policies/voting_state.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';

/// What [checkVotingEligibility] needs to decide.
final class VotingEligibilityInput {
  /// Creates the input of [checkVotingEligibility].
  const new({
    required this.meeting,
    required this.resolutionId,
    required this.voterId,
    required this.queuedVotes,
    required this.now,
  });

  /// The meeting the resolution belongs to.
  final Meeting meeting;

  /// The resolution voted on.
  final ResolutionId resolutionId;

  /// Who wants to vote.
  final UserId voterId;

  /// The votes waiting in the outbox for this resolution, whoever cast them.
  final List<PendingVote> queuedVotes;

  /// The current instant.
  final Instant now;
}

/// May this voter vote on this resolution now? Ok, or the first reason why not,
/// checked in this order:
///
/// 1. the meeting has no such resolution;
/// 2. the voter is not a participant of the meeting;
/// 3. the voter's role carries no vote;
/// 4. the resolution is closed;
/// 5. its voting window is over (`closesAt` is reached: the instant itself is
///    already too late). Both are told by [getVotingState], the one definition
///    of the state of a vote, which the screens use too;
/// 6. the voter has already voted, either a vote the remote source records or
///    one waiting in the outbox. A cast vote is final: there is no second vote
///    and no change of mind.
Result<void, VotingError> checkVotingEligibility(VotingEligibilityInput input) {
  final VotingEligibilityInput(
    :meeting,
    :resolutionId,
    :voterId,
    :queuedVotes,
    :now,
  ) = input;

  final resolution = findResolution(meeting, resolutionId);
  if (resolution == null) {
    return err(ResolutionNotFoundError(resolutionId: resolutionId));
  }

  final participant = findParticipant(meeting, voterId);
  if (participant == null) {
    return err(const NotAParticipantError());
  }
  if (!hasVotingRights(participant)) {
    return err(const NoVotingRightsError());
  }

  switch (getVotingState(resolution, now)) {
    case VotingState.closed:
      return err(const ResolutionClosedError());
    case VotingState.windowOver:
      return err(const VotingWindowOverError());
    case VotingState.open:
      break;
  }

  if (resolution.recordedVote != null) {
    return err(const AlreadyVotedError(source: AlreadyVotedSource.recorded));
  }
  final alreadyQueued = queuedVotes.any(
    (pending) =>
        pending.vote.resolutionId == resolutionId &&
        pending.vote.voterId == voterId,
  );
  if (alreadyQueued) {
    return err(const AlreadyVotedError(source: AlreadyVotedSource.queued));
  }

  return ok<void>(null);
}
