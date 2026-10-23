import 'package:boardroom/application/ports/vote_outbox.dart';
import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/instant.dart';

/// A vote outbox in memory: a queue in the order of enqueueing, scoped by voter
/// on every read, with the idempotent writes the port describes and
/// `markAttempt`, which is not. What it holds is immutable, so nobody holds a
/// reference they could change into the queue. It is not durable: it lives as
/// long as the process, which is what the database adapter fixes. It holds its
/// entries as typed values, so it has no entry that cannot be read.
final class InMemoryVoteOutbox implements VoteOutbox {
  List<OutboxVote> _entries = [];

  @override
  Future<Result<EnqueueResult, StorageWriteFailedError>> enqueue(
    PendingVote pending,
  ) async {
    for (final entry in _entries) {
      if (entry.vote.idempotencyKey == pending.vote.idempotencyKey) {
        return ok(EnqueueResult.alreadyQueued(existing: entry));
      }
    }
    _entries.add(pending);
    return ok(const EnqueueResult.enqueued());
  }

  @override
  Future<Result<OutboxListing, StorageReadFailedError>> list(
    UserId voterId,
  ) async => ok(
    OutboxListing(
      votes: List.unmodifiable(
        _entries.where((entry) => entry.vote.voterId == voterId),
      ),
      unreadable: 0,
    ),
  );

  /// It holds its entries as typed values, so none of them can be unreadable:
  /// nothing to discard.
  @override
  Future<Result<int, StorageWriteFailedError>> discardUnreadable(
    UserId voterId,
  ) async => ok(0);

  @override
  Future<Result<List<OutboxVote>, StorageReadFailedError>> findByResolution(
    ResolutionId resolutionId,
    UserId voterId,
  ) async => ok(
    List.unmodifiable(
      _entries.where(
        (entry) =>
            entry.vote.resolutionId == resolutionId &&
            entry.vote.voterId == voterId,
      ),
    ),
  );

  @override
  Future<Result<void, StorageWriteFailedError>> markAttempt(
    IdempotencyKey key,
  ) async {
    _entries = [
      for (final entry in _entries)
        if (entry.vote.idempotencyKey == key && entry is PendingVote)
          recordAttempt(entry)
        else
          entry,
    ];
    return ok<void>(null);
  }

  @override
  Future<Result<void, StorageWriteFailedError>> reject(
    IdempotencyKey key,
    RejectionReason reason,
    Instant rejectedAt,
  ) async {
    _entries = [
      for (final entry in _entries)
        if (entry.vote.idempotencyKey == key && entry is PendingVote)
          rejectVote(entry, reason, rejectedAt)
        else
          entry,
    ];
    return ok<void>(null);
  }

  @override
  Future<Result<void, StorageWriteFailedError>> remove(
    IdempotencyKey key,
  ) async {
    _entries = [
      for (final entry in _entries)
        if (entry.vote.idempotencyKey != key) entry,
    ];
    return ok<void>(null);
  }
}
