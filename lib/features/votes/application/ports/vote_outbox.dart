import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'vote_outbox.freezed.dart';

/// What `enqueue` did.
enum EnqueueOutcome implements StableValue {
  /// The vote was appended to the outbox.
  enqueued('enqueued'),

  /// A vote with the same idempotency key was already in the outbox: nothing
  /// changed.
  alreadyQueued('alreadyQueued'),

  /// An entry of the outbox that cannot be read holds the key: nothing changed,
  /// and the entry was not overwritten. It is kept until the user discards it
  /// (`discardUnreadable`).
  heldByUnreadable('heldByUnreadable');

  new(this.value);

  @override
  final String value;
}

/// What `enqueue` did, and what it found: one of [Enqueued], [AlreadyQueued]
/// and [HeldByUnreadable]. [outcome] gives it as a stable value.
@freezed
sealed class EnqueueResult with _$EnqueueResult {
  /// The vote was appended to the outbox.
  const factory enqueued() = Enqueued;

  /// A vote with the same idempotency key was already in the outbox.
  const factory alreadyQueued({
    /// The vote that holds the key, pending or rejected.
    required OutboxVote existing,
  }) = AlreadyQueued;

  /// An entry of the outbox that cannot be read holds the key.
  const factory heldByUnreadable() = HeldByUnreadable;

  const new _();

  /// What `enqueue` did.
  EnqueueOutcome get outcome => switch (this) {
    Enqueued() => EnqueueOutcome.enqueued,
    AlreadyQueued() => EnqueueOutcome.alreadyQueued,
    HeldByUnreadable() => EnqueueOutcome.heldByUnreadable,
  };
}

/// The outbox of a voter: the votes it can read, and how many entries it holds
/// and cannot.
@freezed
abstract class OutboxListing with _$OutboxListing {
  /// Creates a listing.
  const factory({
    /// Pending and rejected votes, oldest first (the order of enqueueing).
    required List<OutboxVote> votes,

    /// How many entries of the voter are kept but no longer read back as a vote
    /// (the store was altered, or written by something else). They are not in
    /// `votes`, are never sent, and a read does not delete them: only
    /// `discardUnreadable` does, when the user asks. An outbox that holds its
    /// entries as typed values has none.
    required int unreadable,
  }) = _OutboxListing;
}

/// The durable local queue of votes cast without a network, waiting to be sent,
/// and of the votes that ended rejected until the user acknowledges them. It
/// must survive the app being closed. It is NOT cleared when a user signs out:
/// a vote is scoped by its voter and must be sent when they come back.
///
/// It holds the choices of secret ballots, and it outlives the sign-out, so it
/// needs protection at rest: an adapter stores it encrypted (the keystore / the
/// secure storage of the device), in app-private storage excluded from backups.
/// Its content is never logged. A vote is found by its whole idempotency key:
/// two keys that share a prefix, or differ only in case, are two votes, and a
/// lookup by prefix or substring would merge them.
///
/// It is read and written by `CastVote` (a vote that could not be delivered),
/// `SyncPendingVotes` (the presentation or the composition root triggers it
/// when connectivity is regained and when the app returns to the foreground;
/// the application layer does not watch the network), `ListPendingVotes` and
/// `AcknowledgeRejectedVote`.
///
/// Reads are scoped by voter: `list` and `findByResolution` take the voter and
/// never return the vote of anybody else. A key already holds the voter (see
/// `idempotencyKeyOf`), which scopes the writes.
///
/// **An entry that cannot be read is quarantined, never deleted by a read and
/// never overwritten.** A vote is the choice of a person; an entry that no
/// longer reads back may still be the only trace of it, and a read, or a vote
/// queued under the same key, must not destroy it silently. It is kept out of
/// the queue (it is not sent, nor offered), counted in `list`, and removed only
/// by `discardUnreadable`, which the user asks for knowing how many there are.
/// `reject` and `markAttempt` do not touch it, `remove` does not delete it, and
/// `enqueue` of a vote under its key says so (`heldByUnreadable`) and queues
/// nothing.
///
/// Contract:
/// - No method throws. Only a store that cannot be read or written returns a
///   storage error. Every method settles in bounded time; a store that does not
///   answer in time is a storage error.
/// - Idempotent writes: `enqueue` (a second call with the same key changes
///   nothing and says so), `reject` (rejecting a vote that is already rejected,
///   or unknown, changes nothing), `remove` (removing an unknown key succeeds)
///   and `discardUnreadable`.
/// - NOT idempotent: `markAttempt` counts one more attempt every time it is
///   called.
abstract interface class VoteOutbox {
  /// Appends a pending vote, unless one with the same idempotency key is
  /// already in the outbox, whatever its state. A voter has one vote per
  /// resolution, so a second one is never queued: the answer says which case it
  /// was, and returns the vote that holds the key.
  Future<Result<EnqueueResult, StorageWriteFailedError>> enqueue(
    PendingVote pending,
  );

  /// The votes of a voter, pending and rejected, oldest first, and the count of
  /// the entries it cannot read.
  Future<Result<OutboxListing, StorageReadFailedError>> list(UserId voterId);

  /// Removes the entries of the voter that cannot be read (see above), and says
  /// how many. It is the one way they leave. Idempotent: asking again removes
  /// nothing and says zero. The votes it can read are not touched, nor are the
  /// entries of anybody else.
  Future<Result<int, StorageWriteFailedError>> discardUnreadable(
    UserId voterId,
  );

  /// The votes of a voter on a resolution, pending and rejected. Empty when
  /// there is none.
  Future<Result<List<OutboxVote>, StorageReadFailedError>> findByResolution(
    ResolutionId resolutionId,
    UserId voterId,
  );

  /// Counts one more attempt on a pending vote. Does nothing when the key is
  /// unknown or rejected.
  Future<Result<void, StorageWriteFailedError>> markAttempt(IdempotencyKey key);

  /// Moves a pending vote to the rejected state, with its reason and the
  /// instant (`rejectVote`). Does nothing when the key is unknown or the vote
  /// is already rejected.
  Future<Result<void, StorageWriteFailedError>> reject(
    IdempotencyKey key,
    RejectionReason reason,
    Instant rejectedAt,
  );

  /// Removes a vote, pending or rejected. Does nothing when the key is unknown,
  /// and does not remove an entry that cannot be read (see above).
  Future<Result<void, StorageWriteFailedError>> remove(IdempotencyKey key);
}
