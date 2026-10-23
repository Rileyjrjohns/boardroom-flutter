import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';

/// Where a resolution stands for voting at a given instant. It is the one
/// definition of "can still be voted on": the eligibility policy and the
/// screens both ask [getVotingState], so a resolution cannot be open on a
/// screen and closed for the rules.
enum VotingState implements StableValue {
  /// The status is open and the voting window, if there is one, is not over.
  open('open'),

  /// The status says the resolution is closed.
  closed('closed'),

  /// The status is still open, but the voting window is over (`closesAt` is
  /// reached).
  windowOver('windowOver');

  new(this.value);

  @override
  final String value;
}

/// The state of voting on a resolution at [now]. A closed status wins over the
/// window: a resolution that was closed by hand stays [VotingState.closed]
/// whatever `closesAt` says. The closing instant itself is already too late, as
/// for the eligibility to vote. A resolution without a `closesAt` stays open
/// until its status says otherwise.
VotingState getVotingState(Resolution resolution, Instant now) {
  if (resolution.status == ResolutionStatus.closed) {
    return VotingState.closed;
  }
  final closesAt = resolution.closesAt;
  if (closesAt != null && isAtOrAfter(now, closesAt)) {
    return VotingState.windowOver;
  }
  return VotingState.open;
}
