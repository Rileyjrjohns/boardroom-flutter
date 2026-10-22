part of 'app_error.dart';

/// What can go wrong between a vote being cast and the server recording it.
enum VoteDeliveryErrorCode implements StableValue {
  /// Sending the vote failed unexpectedly too many times.
  undeliverable('voteUndeliverable'),

  /// An earlier vote of the same voter on the resolution is still rejected.
  previouslyRejected('votePreviouslyRejected'),

  /// A vote on the same resolution is being cast right now.
  inProgress('voteInProgress'),

  /// Only a rejected vote can be acknowledged.
  notRejected('voteNotRejected');

  new(this.value);

  @override
  final String value;
}

/// Why a queued vote ended in the rejected state: the server refused it
/// ([VotingError]), or it was given up ([VoteUndeliverableError]).
sealed class RejectionReason extends AppError {
  /// Creates a rejection reason.
  const new();
}

/// The vote could not be delivered: sending it failed unexpectedly [attempts]
/// times, and the app gave up. It is a reason a queued vote is moved to the
/// rejected state, so that the user sees it.
final class VoteUndeliverableError extends RejectionReason {
  /// Creates the error, after [attempts] attempts.
  const new({required this.attempts});

  /// How many times sending the vote failed.
  final int attempts;

  @override
  String get code => VoteDeliveryErrorCode.undeliverable.value;

  @override
  Map<String, Object?> get payload => {'attempts': attempts};
}

/// A new vote on a resolution was refused because an earlier vote of the same
/// voter on it is still in the outbox, rejected. The user acknowledges the
/// rejected vote before anything else.
final class VotePreviouslyRejectedError extends AppError {
  /// Creates the error, with why the earlier vote was rejected.
  const new({required this.reason});

  /// Why the earlier vote was rejected.
  final RejectionReason reason;

  @override
  String get code => VoteDeliveryErrorCode.previouslyRejected.value;

  @override
  Map<String, Object?> get payload => {'reason': reason};
}

/// A vote on the same resolution is being cast right now (on this instance of
/// the use case).
final class VoteInProgressError extends AppError {
  /// Creates the error.
  const new();

  @override
  String get code => VoteDeliveryErrorCode.inProgress.value;
}

/// Only a rejected vote can be acknowledged; this one is still waiting to be
/// sent.
final class VoteNotRejectedError extends AppError {
  /// Creates the error.
  const new();

  @override
  String get code => VoteDeliveryErrorCode.notRejected.value;
}

/// Builds a [VoteUndeliverableError] after [attempts] attempts.
VoteUndeliverableError voteUndeliverable(int attempts) =>
    VoteUndeliverableError(attempts: attempts);

/// Builds a [VotePreviouslyRejectedError] for an earlier vote rejected for
/// [reason].
VotePreviouslyRejectedError votePreviouslyRejected(RejectionReason reason) =>
    VotePreviouslyRejectedError(reason: reason);

/// Builds a [VoteInProgressError].
VoteInProgressError voteInProgress() => const VoteInProgressError();

/// Builds a [VoteNotRejectedError].
VoteNotRejectedError voteNotRejected() => const VoteNotRejectedError();
