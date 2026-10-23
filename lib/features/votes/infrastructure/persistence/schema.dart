import 'package:boardroom/core/domain/shared/constants.dart';

// The names of what the votes store on the device. They are part of the format
// of the database: a database created by an older version of the app has these
// names in it. Changing one is a migration (see
// `lib/app/persistence/migrations.dart`, which lists the history of the whole
// file and reads these names), never an edit of a constant.

/// The tables of the votes.
enum VoteStoredTable implements StableValue {
  /// The votes waiting to be sent, and the ones that were rejected.
  outboxVotes('outbox_votes'),

  /// Exists during version 3 of the schema only: the outbox, rebuilt (see
  /// `lib/app/persistence/migrations.dart`).
  outboxVotesRebuilt('outbox_votes_v3');

  new(this.value);

  @override
  final String value;
}

/// The columns of the tables of the votes.
enum VoteStoredColumn implements StableValue {
  /// The order of enqueueing: never reused, and the order the outbox is read
  /// in.
  sequence('sequence'),

  /// The key a vote is found by.
  idempotencyKey('idempotency_key'),

  /// Who voted.
  voterId('voter_id'),

  /// The resolution voted on.
  resolutionId('resolution_id'),

  /// The meeting of a vote.
  meetingId('meeting_id'),

  /// What the voter answered.
  choice('choice'),

  /// When the vote was cast.
  castAt('cast_at'),

  /// When the vote was queued.
  enqueuedAt('enqueued_at'),

  /// How many times sending the vote failed.
  attempts('attempts'),

  /// Pending, rejected or quarantined.
  status('status'),

  /// Why a vote was rejected, as JSON. Null while it is pending.
  rejectionReason('rejection_reason'),

  /// When the vote was rejected.
  rejectedAt('rejected_at');

  new(this.value);

  @override
  final String value;
}

/// The indexes of the tables of the votes.
enum VoteStoredIndex implements StableValue {
  /// Finds the votes of a voter on a resolution.
  outboxByResolution('outbox_votes_by_voter_and_resolution');

  new(this.value);

  @override
  final String value;
}

/// The status of an entry of the outbox that no longer reads back as a vote,
/// kept as it is. It is a status of the table only: the domain knows a vote as
/// pending or rejected. Added by version 3 of the schema (see
/// `lib/app/persistence/migrations.dart`).
const String outboxQuarantined = 'quarantined';
