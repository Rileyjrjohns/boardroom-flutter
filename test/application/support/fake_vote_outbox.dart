import 'dart:async';

import 'package:boardroom/application/ports/vote_outbox.dart';
import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/instant.dart';

import 'copy_plain.dart';

/// An entry the fake keeps but cannot read: what the voter owns and the key it
/// sits under.
typedef UnreadableEntry = ({UserId voterId, String key});

/// An in-memory queue that honours the contract of the port: FIFO, reads scoped
/// by voter, the idempotent writes, and `markAttempt` that is not. It keeps
/// copies of what it is given and hands back copies of what it holds. A test
/// can plant entries it cannot read (`seedUnreadable`), which it quarantines
/// the way the port says.
class FakeVoteOutbox implements VoteOutbox {
  /// Makes `list` fail while set.
  StorageReadFailedError? listFailure;

  /// Makes `findByResolution` fail while set.
  StorageReadFailedError? findFailure;

  /// Makes `enqueue` fail while set (nothing is queued).
  StorageWriteFailedError? enqueueFailure;

  /// Makes `markAttempt` fail while set.
  StorageWriteFailedError? markAttemptFailure;

  /// Makes `reject` fail while set (the vote stays pending).
  StorageWriteFailedError? rejectFailure;

  /// Makes `remove` fail while set (the vote stays).
  StorageWriteFailedError? removeFailure;

  /// Makes `discardUnreadable` fail while set (nothing is discarded).
  StorageWriteFailedError? discardFailure;

  /// Called when `list`, `findByResolution` or `discardUnreadable` is asked,
  /// before the outbox answers: a test uses it to change the world while the
  /// read is in flight (another user signs in, say). The answer is still the
  /// one for the voter that was asked about.
  FutureOr<void> Function()? onRequest;

  List<OutboxVote> _entries = [];
  List<UnreadableEntry> _unreadable = [];

  /// Puts votes in the queue without going through the port.
  void seed(List<OutboxVote> entries) {
    _entries.addAll(entries.map(copyPlain));
  }

  /// Plants an entry of the voter that cannot be read, under a key.
  void seedUnreadable(UserId voterId, [String key = 'unreadable']) {
    _unreadable.add((voterId: voterId, key: key));
  }

  /// The entries nobody can read that are kept, of every voter.
  List<UnreadableEntry> unreadableSnapshot() => List.of(_unreadable);

  /// The whole queue, of every voter, oldest first.
  List<OutboxVote> snapshot() => List.of(_entries);

  @override
  Future<Result<EnqueueResult, StorageWriteFailedError>> enqueue(
    PendingVote pending,
  ) async {
    final failure = enqueueFailure;
    if (failure != null) {
      return err(failure);
    }
    if (_unreadable.any((entry) => entry.key == pending.vote.idempotencyKey)) {
      return ok(const EnqueueResult.heldByUnreadable());
    }
    final existing = _entries
        .where(
          (entry) => entry.vote.idempotencyKey == pending.vote.idempotencyKey,
        )
        .firstOrNull;
    if (existing != null) {
      return ok(EnqueueResult.alreadyQueued(existing: copyPlain(existing)));
    }
    _entries.add(copyPlain(pending));
    return ok(const EnqueueResult.enqueued());
  }

  @override
  Future<Result<OutboxListing, StorageReadFailedError>> list(
    UserId voterId,
  ) async {
    await onRequest?.call();
    final failure = listFailure;
    if (failure != null) {
      return err(failure);
    }
    return ok(
      OutboxListing(
        votes: copyPlain(
          _entries.where((entry) => entry.vote.voterId == voterId).toList(),
        ),
        unreadable: _unreadable
            .where((entry) => entry.voterId == voterId)
            .length,
      ),
    );
  }

  @override
  Future<Result<int, StorageWriteFailedError>> discardUnreadable(
    UserId voterId,
  ) async {
    await onRequest?.call();
    final failure = discardFailure;
    if (failure != null) {
      return err(failure);
    }
    final before = _unreadable.length;
    _unreadable = _unreadable
        .where((entry) => entry.voterId != voterId)
        .toList();
    return ok(before - _unreadable.length);
  }

  @override
  Future<Result<List<OutboxVote>, StorageReadFailedError>> findByResolution(
    ResolutionId resolutionId,
    UserId voterId,
  ) async {
    await onRequest?.call();
    final failure = findFailure;
    if (failure != null) {
      return err(failure);
    }
    return ok(
      copyPlain(
        _entries
            .where(
              (entry) =>
                  entry.vote.resolutionId == resolutionId &&
                  entry.vote.voterId == voterId,
            )
            .toList(),
      ),
    );
  }

  @override
  Future<Result<void, StorageWriteFailedError>> markAttempt(
    IdempotencyKey key,
  ) async {
    final failure = markAttemptFailure;
    if (failure != null) {
      return err(failure);
    }
    _entries = [
      for (final entry in _entries)
        if (entry is PendingVote && entry.vote.idempotencyKey == key)
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
    final failure = rejectFailure;
    if (failure != null) {
      return err(failure);
    }
    _entries = [
      for (final entry in _entries)
        if (entry is PendingVote && entry.vote.idempotencyKey == key)
          rejectVote(entry, copyPlain(reason), rejectedAt)
        else
          entry,
    ];
    return ok<void>(null);
  }

  @override
  Future<Result<void, StorageWriteFailedError>> remove(
    IdempotencyKey key,
  ) async {
    final failure = removeFailure;
    if (failure != null) {
      return err(failure);
    }
    _entries = [
      for (final entry in _entries)
        if (entry.vote.idempotencyKey != key) entry,
    ];
    return ok<void>(null);
  }
}
