import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/constants.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/shared/validation.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'outbox_vote.freezed.dart';

const int _maxAttempts = 1000000;

/// Where a vote of the outbox stands.
enum OutboxStatus implements StableValue {
  /// Waiting to be sent.
  pending('pending'),

  /// Refused by the server, or given up. It will not be sent again.
  rejected('rejected');

  new(this.value);

  @override
  final String value;
}

/// A vote of the outbox: either waiting to be sent ([PendingVote]) or kept but
/// never to be sent ([RejectedVote]). The state is told by the class, and
/// [status] gives it as a stable value.
@freezed
sealed class OutboxVote with _$OutboxVote {
  /// A vote waiting in the outbox to be sent.
  const factory pending({
    required Vote vote,
    required Instant enqueuedAt,

    /// How many times sending it failed in a way that says nothing about the
    /// vote itself.
    required int attempts,
  }) = PendingVote;

  /// A vote the outbox keeps but will never send: the server refused it for a
  /// business reason, or the app gave up on it (`undeliverable`). It stays
  /// until the user acknowledges it. The reason is part of the state: a
  /// rejected vote without a reason, or a pending one with a reason, cannot
  /// exist.
  const factory rejected({
    required Vote vote,
    required Instant enqueuedAt,
    required int attempts,
    required RejectionReason reason,
    required Instant rejectedAt,
  }) = RejectedVote;

  const new _();

  /// Where the vote stands.
  OutboxStatus get status => switch (this) {
    PendingVote() => OutboxStatus.pending,
    RejectedVote() => OutboxStatus.rejected,
  };
}

/// A vote that has just been queued: no attempt yet.
PendingVote createPendingVote(Vote vote, Instant enqueuedAt) =>
    PendingVote(vote: vote, enqueuedAt: enqueuedAt, attempts: 0);

/// Rebuilds a pending vote read back from storage, checking its attempt count.
/// The count is a `num` because it comes from outside (a stored row) and may
/// be a fraction.
Result<PendingVote, ValidationError> restorePendingVote({
  required Vote vote,
  required Instant enqueuedAt,
  required num attempts,
}) => map(
  requireIntegerInRange(
    ValidationField.attemptCount,
    attempts,
    0,
    _maxAttempts,
  ),
  (count) => PendingVote(vote: vote, enqueuedAt: enqueuedAt, attempts: count),
);

/// The same pending vote, with one more attempt counted.
PendingVote recordAttempt(PendingVote pending) =>
    pending.copyWith(attempts: pending.attempts + 1);

/// The pending vote, moved to the rejected state. Only a pending vote can be
/// rejected.
RejectedVote rejectVote(
  PendingVote pending,
  RejectionReason reason,
  Instant rejectedAt,
) => RejectedVote(
  vote: pending.vote,
  enqueuedAt: pending.enqueuedAt,
  attempts: pending.attempts,
  reason: reason,
  rejectedAt: rejectedAt,
);

/// Whether the entry is waiting to be sent.
bool isPending(OutboxVote entry) => entry is PendingVote;

/// Whether the entry was rejected and will not be sent.
bool isRejected(OutboxVote entry) => entry is RejectedVote;
