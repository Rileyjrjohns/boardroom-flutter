import 'dart:convert';

import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/ports/vote_outbox.dart';
import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/domain/value_objects/vote_choice.dart';
import 'package:boardroom/infrastructure/http/dto/wire.dart';
import 'package:boardroom/infrastructure/persistence/boardroom_database.dart';
import 'package:boardroom/infrastructure/persistence/guarded.dart';
import 'package:boardroom/infrastructure/persistence/schema.dart';
import 'package:boardroom/infrastructure/shared/rejection_schemas.dart';
import 'package:drift/drift.dart';

/// What a row of the outbox is called in the logs.
const String _outboxVoteResource = 'outboxVote';
const String _unreadableCause = 'stored vote unreadable';

// The statements that read. A vote is found by its whole idempotency key (a
// `UNIQUE` column compared byte for byte). The writes go through the tables of
// drift (`tables.dart`).
String get _votes => StoredTable.outboxVotes.value;
String get _sequence => StoredColumn.sequence.value;
String get _idempotencyKey => StoredColumn.idempotencyKey.value;
String get _voterId => StoredColumn.voterId.value;
String get _resolutionId => StoredColumn.resolutionId.value;
String get _meetingId => StoredColumn.meetingId.value;
String get _choice => StoredColumn.choice.value;
String get _castAt => StoredColumn.castAt.value;
String get _enqueuedAt => StoredColumn.enqueuedAt.value;
String get _attempts => StoredColumn.attempts.value;
String get _status => StoredColumn.status.value;
String get _rejectionReason => StoredColumn.rejectionReason.value;
String get _rejectedAt => StoredColumn.rejectedAt.value;

String get _select =>
    'SELECT $_sequence, $_idempotencyKey, $_voterId, $_resolutionId, '
    '$_meetingId, $_choice, $_castAt, $_enqueuedAt, $_attempts, $_status, '
    '$_rejectionReason, $_rejectedAt FROM $_votes';
String get _selectByKey => '$_select WHERE $_idempotencyKey = ?';
String get _selectByVoter => '$_select WHERE $_voterId = ? ORDER BY $_sequence';
String get _selectByResolution =>
    '$_select WHERE $_voterId = ? AND $_resolutionId = ? '
    'ORDER BY $_sequence';

/// The columns of a row, as the engine hands them over, each one with the type
/// the table gives it. A row that has another (a text in a number column) is
/// not a vote.
final class _Row {
  const new({
    required this.sequence,
    required this.idempotencyKey,
    required this.voterId,
    required this.resolutionId,
    required this.meetingId,
    required this.choice,
    required this.castAt,
    required this.enqueuedAt,
    required this.attempts,
    required this.status,
    required this.rejectionReason,
    required this.rejectedAt,
  });

  /// The row, or `null` when a column has the wrong type.
  static _Row? of(Map<String, Object?> raw) {
    final sequence = raw[_sequence];
    final idempotencyKey = raw[_idempotencyKey];
    final voterId = raw[_voterId];
    final resolutionId = raw[_resolutionId];
    final meetingId = raw[_meetingId];
    final choice = raw[_choice];
    final castAt = raw[_castAt];
    final enqueuedAt = raw[_enqueuedAt];
    final attempts = raw[_attempts];
    final status = raw[_status];
    final rejectionReason = raw[_rejectionReason];
    final rejectedAt = raw[_rejectedAt];
    if (sequence is! num ||
        idempotencyKey is! String ||
        voterId is! String ||
        resolutionId is! String ||
        meetingId is! String ||
        choice is! String ||
        castAt is! num ||
        enqueuedAt is! num ||
        attempts is! num ||
        status is! String ||
        (rejectionReason != null && rejectionReason is! String) ||
        (rejectedAt != null && rejectedAt is! num)) {
      return null;
    }
    return _Row(
      sequence: sequence,
      idempotencyKey: idempotencyKey,
      voterId: voterId,
      resolutionId: resolutionId,
      meetingId: meetingId,
      choice: choice,
      castAt: castAt,
      enqueuedAt: enqueuedAt,
      attempts: attempts,
      status: status,
      rejectionReason: rejectionReason as String?,
      rejectedAt: rejectedAt as num?,
    );
  }

  final num sequence;
  final String idempotencyKey;
  final String voterId;
  final String resolutionId;
  final String meetingId;
  final String choice;
  final num castAt;
  final num enqueuedAt;
  final num attempts;
  final String status;
  final String? rejectionReason;
  final num? rejectedAt;
}

/// What a row came to, when it was read: a vote, or nothing that can be read as
/// one.
sealed class _Decoded {
  const new();
}

final class _ReadableVote extends _Decoded {
  const new(this.vote);

  final OutboxVote vote;
}

final class _UnreadableRow extends _Decoded {
  const new({required this.sequence, required this.known});

  /// The number of the row, which is how it is found again.
  final int sequence;

  /// Whether the row was already quarantined, and reported, before this read.
  final bool known;
}

/// The outbox of votes on SQLite, through drift: durable, first in first out by
/// the order of enqueueing (the `sequence` of the row, which only grows: never
/// a timestamp), scoped by voter.
///
/// - A vote is held in columns, found by its whole idempotency key (a `UNIQUE`
///   column compared byte for byte: two keys that share a prefix or differ by
///   case are two votes). `enqueue` checks the key and inserts in one
///   transaction, so two callers with the same key enqueue it once and both are
///   told.
/// - Pending or rejected is a column with a check: a rejected vote always has
///   its reason and its instant, a pending one never does.
/// - What is read back is checked against the factories of the domain, and the
///   key must be the one the vote derives. A row that no longer passes (the
///   file was altered, or written by something else) is not a vote anybody can
///   send, but it may be the only trace of one: it is **quarantined**, not
///   deleted. Its status becomes `quarantined` and nothing else about it
///   changes, it is reported to the monitoring without its content, it is left
///   out of the answers and counted in `list`, a vote queued under its key is
///   refused rather than written over it, and only `discardUnreadable` deletes
///   it. A row is attributed to a voter by its `voter_id` text, whatever the
///   rest holds; one whose `voter_id` is no voter's belongs to nobody who can
///   ever sign in, and stays where it is. It never throws.
/// - Every call settles: a statement that does not answer in time is a storage
///   error.
///
/// It holds the choices of a secret ballot and outlives the sign-out, so the
/// database it lives in is encrypted (see `openProtectedDatabase`).
final class DriftVoteOutbox implements VoteOutbox {
  /// Creates the outbox over [database]. [timeoutMillis] is how long a
  /// statement may take (`defaultStatementTimeoutMillis` by default).
  const new({
    required this.database,
    required this.monitoring,
    this.timeoutMillis,
  });

  /// The database the votes are in.
  final BoardroomDatabase database;

  /// Where a row that cannot be read is reported.
  final Monitoring monitoring;

  /// How long a statement may take.
  final int? timeoutMillis;

  int get _timeout => timeoutMillis ?? defaultStatementTimeoutMillis;

  $OutboxVotesTable get _table => database.outboxVotes;

  @override
  Future<Result<EnqueueResult, StorageWriteFailedError>> enqueue(
    PendingVote pending,
  ) => guardedWrite(
    () => database.transaction<EnqueueResult>(() async {
      final vote = pending.vote;
      final held = await _rowsByKey(vote.idempotencyKey);
      if (held.isNotEmpty) {
        switch (_decode(held.first)) {
          case _ReadableVote(vote: final existing):
            return EnqueueResult.alreadyQueued(existing: existing);
          case _UnreadableRow(:final sequence, :final known):
            // A row that holds the key but is no vote is kept as it is, and
            // the vote is not queued.
            if (!known) {
              await _quarantine(sequence);
            }
            return const EnqueueResult.heldByUnreadable();
        }
      }
      await _table.insertOne(
        OutboxVotesCompanion.insert(
          idempotencyKey: vote.idempotencyKey,
          voterId: vote.voterId,
          resolutionId: vote.resolutionId,
          meetingId: vote.meetingId,
          choice: vote.choice.value,
          castAt: vote.castAt,
          enqueuedAt: pending.enqueuedAt,
          attempts: pending.attempts,
          status: OutboxStatus.pending.value,
        ),
      );
      return const EnqueueResult.enqueued();
    }),
    _timeout,
  );

  @override
  Future<Result<OutboxListing, StorageReadFailedError>> list(UserId voterId) =>
      _readVotes(_selectByVoter, [Variable.withString(voterId)]);

  @override
  Future<Result<List<OutboxVote>, StorageReadFailedError>> findByResolution(
    ResolutionId resolutionId,
    UserId voterId,
  ) async {
    final read = await _readVotes(_selectByResolution, [
      Variable.withString(voterId),
      Variable.withString(resolutionId),
    ]);
    return map(read, (listing) => listing.votes);
  }

  @override
  Future<Result<int, StorageWriteFailedError>> discardUnreadable(
    UserId voterId,
  ) => guardedWrite(
    () => database.transaction(() async {
      var discarded = 0;
      final rows = await database
          .customSelect(
            _selectByVoter,
            variables: [Variable.withString(voterId)],
          )
          .get();
      for (final raw in rows) {
        if (_decode(raw.data, report: false) case _UnreadableRow(
          :final sequence,
        )) {
          await (database.delete(
            _table,
          )..where((row) => row.sequence.equals(sequence))).go();
          discarded += 1;
        }
      }
      return discarded;
    }),
    _timeout,
  );

  @override
  Future<Result<void, StorageWriteFailedError>> markAttempt(
    IdempotencyKey key,
  ) => _changeVote(
    key,
    () =>
        (database.update(_table)..where(
              (row) =>
                  row.idempotencyKey.equals(key) &
                  row.status.equals(OutboxStatus.pending.value),
            ))
            .write(
              OutboxVotesCompanion.custom(
                attempts: _table.attempts + const Constant(1),
              ),
            ),
  );

  @override
  Future<Result<void, StorageWriteFailedError>> reject(
    IdempotencyKey key,
    RejectionReason reason,
    Instant rejectedAt,
  ) => _changeVote(
    key,
    () =>
        (database.update(_table)..where(
              (row) =>
                  row.idempotencyKey.equals(key) &
                  row.status.equals(OutboxStatus.pending.value),
            ))
            .write(
              OutboxVotesCompanion(
                status: Value(OutboxStatus.rejected.value),
                rejectionReason: Value(
                  jsonEncode(toRejectionReasonWire(reason).toJson()),
                ),
                rejectedAt: Value(rejectedAt),
              ),
            ),
  );

  @override
  Future<Result<void, StorageWriteFailedError>> remove(IdempotencyKey key) =>
      _changeVote(
        key,
        () => (database.delete(
          _table,
        )..where((row) => row.idempotencyKey.equals(key))).go(),
      );

  /// Runs [change] on the vote held under a key, only if the row under that
  /// key can be read as a vote. The row is looked at first, in the same
  /// transaction: a row that cannot be read is not the outbox's to change, nor
  /// to delete, whatever its status says. It is quarantined if it was not
  /// already, and [change] is not run.
  Future<Result<void, StorageWriteFailedError>> _changeVote(
    IdempotencyKey key,
    Future<void> Function() change,
  ) async {
    final done = await guardedWrite(
      () => database.transaction(() async {
        final held = await _rowsByKey(key);
        if (held.isEmpty) {
          return;
        }
        switch (_decode(held.first)) {
          case _ReadableVote():
            await change();
          case _UnreadableRow(:final sequence, :final known):
            if (!known) {
              await _quarantine(sequence);
            }
        }
      }),
      _timeout,
    );
    if (done case Err(:final error)) {
      return err(error);
    }
    return ok<void>(null);
  }

  Future<Result<OutboxListing, StorageReadFailedError>> _readVotes(
    String statement,
    List<Variable<Object>> params,
  ) async {
    final selected = await guardedRead(
      () => database.customSelect(statement, variables: params).get(),
      _timeout,
    );
    final List<QueryRow> rows;
    switch (selected) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        rows = value;
    }

    final votes = <OutboxVote>[];
    var unreadable = 0;
    for (final raw in rows) {
      switch (_decode(raw.data)) {
        case _ReadableVote(:final vote):
          votes.add(vote);
        case _UnreadableRow(:final sequence, :final known):
          unreadable += 1;
          if (!known) {
            // Best effort: the row is left out of the answer whether or not it
            // can be marked, and it is looked at again at the next read.
            await guardedWrite(() => _quarantine(sequence), _timeout);
          }
      }
    }
    return ok(OutboxListing(votes: votes, unreadable: unreadable));
  }

  Future<List<Map<String, Object?>>> _rowsByKey(IdempotencyKey key) async {
    final rows = await database
        .customSelect(_selectByKey, variables: [Variable.withString(key)])
        .get();
    return [for (final row in rows) row.data];
  }

  Future<void> _quarantine(int sequence) async {
    await (database.update(_table)
          ..where((row) => row.sequence.equals(sequence)))
        .write(const OutboxVotesCompanion(status: Value(outboxQuarantined)));
  }

  /// What a row holds: a vote, or nothing that can be read as one. A row that
  /// is already quarantined is known and not reported again; one that has just
  /// failed to read is reported to the monitoring, without its content (unless
  /// the caller is about to delete it for the user).
  _Decoded _decode(Map<String, Object?> raw, {bool report = true}) {
    final sequence = raw[_sequence];
    final number = sequence is num ? sequence.toInt() : -1;
    if (raw[_status] == outboxQuarantined) {
      return _UnreadableRow(sequence: number, known: true);
    }

    final vote = _outboxVoteOf(raw);
    if (vote != null) {
      return _ReadableVote(vote);
    }

    if (report) {
      monitoring.captureError(
        MonitoringEvent.storedRowQuarantined,
        storageReadFailed(_unreadableCause),
        {LogAttribute.resource: _outboxVoteResource},
      );
    }
    return _UnreadableRow(sequence: number, known: false);
  }
}

/// The vote of a row, through the factories of the domain.
OutboxVote? _outboxVoteOf(Map<String, Object?> raw) {
  final row = _Row.of(raw);
  if (row == null) {
    return null;
  }

  final PendingVote pending;
  switch (_pendingVoteOf(row)) {
    case Ok(:final value) when value.vote.idempotencyKey == row.idempotencyKey:
      pending = value;
    default:
      return null;
  }

  if (row.status == OutboxStatus.pending.value) {
    return row.rejectionReason == null && row.rejectedAt == null
        ? pending
        : null;
  }
  if (row.status != OutboxStatus.rejected.value) {
    return null;
  }

  final reason = _reasonOf(row.rejectionReason);
  final rejectedAt = parseInstant(row.rejectedAt ?? double.nan);
  if (reason != null && rejectedAt is Ok<Instant, ValidationError>) {
    return rejectVote(pending, reason, rejectedAt.value);
  }
  return null;
}

Result<PendingVote, ValidationError> _pendingVoteOf(_Row row) => andThen(
  parseResolutionId(row.resolutionId),
  (resolutionId) => andThen(
    parseMeetingId(row.meetingId),
    (meetingId) => andThen(
      parseUserId(row.voterId),
      (voterId) => andThen(
        parseVoteChoice(row.choice),
        (choice) => andThen(
          parseInstant(row.castAt),
          (castAt) => andThen(
            parseInstant(row.enqueuedAt),
            (enqueuedAt) => restorePendingVote(
              vote: createVote(
                VoteInput(
                  resolutionId: resolutionId,
                  meetingId: meetingId,
                  voterId: voterId,
                  choice: choice,
                  castAt: castAt,
                ),
              ),
              enqueuedAt: enqueuedAt,
              attempts: row.attempts,
            ),
          ),
        ),
      ),
    ),
  ),
);

/// The reason a rejected vote was kept for, or `null` when what is stored does
/// not read back as one.
RejectionReason? _reasonOf(String? stored) {
  if (stored == null) {
    return null;
  }
  final Object? json;
  try {
    json = jsonDecode(stored);
  } on FormatException {
    return null;
  }
  final wire = decodeWire(json, rejectionReasonWireFromJson);
  if (wire case Ok(:final value)) {
    if (toRejectionReason(value) case Ok(:final value)) {
      return value;
    }
  }
  return null;
}
