part of 'vote_errors.dart';

/// Why a vote cannot be cast. The same reasons come back from the remote source
/// when it rejects one.
enum VotingErrorCode implements StableValue {
  /// The meeting has no such resolution.
  resolutionNotFound('resolutionNotFound'),

  /// The voter is not invited to the meeting.
  notAParticipant('notAParticipant'),

  /// The voter takes part in the meeting without the right to vote.
  noVotingRights('noVotingRights'),

  /// The resolution is closed.
  resolutionClosed('resolutionClosed'),

  /// The resolution is still open, but its closing instant has been reached.
  votingWindowOver('votingWindowOver'),

  /// The voter has already voted on this resolution.
  alreadyVoted('alreadyVoted');

  new(this.value);

  @override
  final String value;
}

/// Where the earlier vote of the voter is.
enum AlreadyVotedSource implements StableValue {
  /// The remote source holds it (it is part of the meeting).
  recorded('recorded'),

  /// It waits in the outbox to be sent.
  queued('queued');

  new(this.value);

  @override
  final String value;
}

/// A business rejection of a vote.
sealed class VotingError extends RejectionReason {
  /// Creates a voting error.
  const new();
}

/// The meeting has no such resolution.
final class ResolutionNotFoundError extends VotingError {
  /// Creates the error for the resolution that was not found.
  const new({required this.resolutionId});

  /// The resolution that the meeting does not have.
  final ResolutionId resolutionId;

  @override
  String get code => VotingErrorCode.resolutionNotFound.value;

  @override
  Map<String, Object?> get payload => {'resolutionId': resolutionId};
}

/// The voter is not invited to the meeting.
final class NotAParticipantError extends VotingError {
  /// Creates the error.
  const new();

  @override
  String get code => VotingErrorCode.notAParticipant.value;
}

/// The voter takes part in the meeting without the right to vote (a secretary,
/// a guest).
final class NoVotingRightsError extends VotingError {
  /// Creates the error.
  const new();

  @override
  String get code => VotingErrorCode.noVotingRights.value;
}

/// The resolution is closed.
final class ResolutionClosedError extends VotingError {
  /// Creates the error.
  const new();

  @override
  String get code => VotingErrorCode.resolutionClosed.value;
}

/// The resolution is still marked open, but its closing instant has been
/// reached.
final class VotingWindowOverError extends VotingError {
  /// Creates the error.
  const new();

  @override
  String get code => VotingErrorCode.votingWindowOver.value;
}

/// A vote is final: the voter has already voted on this resolution.
final class AlreadyVotedError extends VotingError {
  /// Creates the error, with where the earlier vote is.
  const new({required this.source});

  /// Where the earlier vote of the voter is.
  final AlreadyVotedSource source;

  @override
  String get code => VotingErrorCode.alreadyVoted.value;

  @override
  Map<String, Object?> get payload => {'source': source};
}

/// Tells a business rejection of a vote from the other errors. In Dart the
/// `is` check does the same and promotes the variable; this function is kept
/// for the callers that want a plain boolean.
bool isVotingError(AppError error) => error is VotingError;
