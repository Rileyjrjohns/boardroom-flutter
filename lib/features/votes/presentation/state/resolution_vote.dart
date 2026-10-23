import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/use_cases/list_pending_votes.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/domain/policies/voting_eligibility.dart';

/// Where the vote of the user stands on one resolution, for the screen.
sealed class ResolutionVoteView {
  const new();
}

/// What decides it (who the user is, what waits in the outbox) is still being
/// read.
final class VoteViewLoading extends ResolutionVoteView {
  /// Creates the view.
  const new();
}

/// It could not be read: nothing is said about the vote, and nothing can be
/// cast.
final class VoteViewUnavailable extends ResolutionVoteView {
  /// Creates the view.
  const new();
}

/// The user may vote now.
final class VoteViewEligible extends ResolutionVoteView {
  /// Creates the view.
  const new();
}

/// The user voted and the vote waits in the outbox to be sent.
final class VoteViewQueued extends ResolutionVoteView {
  /// Creates the view of a vote for [choice].
  const new(this.choice);

  /// What the user chose.
  final VoteChoice choice;
}

/// The vote of the user was refused, or given up, and they have not yet
/// acknowledged it.
final class VoteViewRejected extends ResolutionVoteView {
  /// Creates the view of a vote refused for [reason].
  const new(this.reason);

  /// Why.
  final RejectionReason reason;
}

/// The user may not vote, and the rule says why.
final class VoteViewIneligible extends ResolutionVoteView {
  /// Creates the view.
  const new(this.error, {this.role});

  /// The reason the rule gives.
  final VotingError error;

  /// The role of the user in the meeting, told when it is what keeps them from
  /// voting.
  final ParticipantRole? role;
}

/// What `resolutionVoteView` needs.
final class ResolutionVoteInput {
  /// Creates the input.
  const new({
    required this.meeting,
    required this.resolution,
    required this.voterId,
    required this.outbox,
    required this.now,
  });

  /// The meeting as it was loaded.
  final Meeting meeting;

  /// The resolution the view is about.
  final Resolution resolution;

  /// Who votes.
  final UserId voterId;

  /// What waits in the outbox of the voter.
  final OutboxContent outbox;

  /// The instant the meeting was loaded at: the screen reads no clock.
  final Instant now;
}

/// What the screen says about the vote of the user on a resolution. The rule is
/// not written here: whether the user may vote is `checkVotingEligibility`, the
/// one the use case `CastVote` applies, run on the meeting that was loaded and
/// on the votes of the outbox; this only orders what the screen has to tell,
/// most urgent first:
///
/// 1. a vote of the user that was refused and not yet acknowledged: it blocks a
///    new vote, and the user has to see why;
/// 2. a vote that waits to be sent, with the choice, whether or not the rule
///    would let them vote now (it will be judged again by the server when it is
///    sent);
/// 3. the reason the rule gives for not voting;
/// 4. otherwise, the right to vote.
ResolutionVoteView resolutionVoteView(ResolutionVoteInput input) {
  final ResolutionVoteInput(:meeting, :resolution, :voterId, :outbox, :now) =
      input;

  for (final entry in outbox.rejected) {
    if (entry.vote.resolutionId == resolution.id) {
      return VoteViewRejected(entry.reason);
    }
  }
  for (final entry in outbox.pending) {
    if (entry.vote.resolutionId == resolution.id) {
      return VoteViewQueued(entry.vote.choice);
    }
  }

  final eligibility = checkVotingEligibility(
    VotingEligibilityInput(
      meeting: meeting,
      resolutionId: resolution.id,
      voterId: voterId,
      // Nothing of this resolution waits in the outbox: a queued vote was
      // answered above.
      queuedVotes: const [],
      now: now,
    ),
  );
  return switch (eligibility) {
    Ok() => const VoteViewEligible(),
    Err(:final error) => VoteViewIneligible(
      error,
      role: error is NoVotingRightsError
          ? findParticipant(meeting, voterId)?.role
          : null,
    ),
  };
}
