import 'package:boardroom/domain/shared/constants.dart';

// The names of what is stored on the device. They are part of the format of the
// database: a database created by an older version of the app has these names
// in it. Changing one is a migration (see `migrations.dart`), never an edit of
// a constant.

/// The tables of the database.
enum StoredTable implements StableValue {
  /// The pages of the list of meetings.
  meetingPages('meeting_pages'),

  /// The meetings viewed.
  meetingDetails('meeting_details'),

  /// The documents already viewed, with where their content is. Added by
  /// version 4 of the schema.
  documentEntries('document_entries'),

  /// The votes waiting to be sent, and the ones that were rejected.
  outboxVotes('outbox_votes'),

  /// Exists during version 3 of the schema only: the outbox, rebuilt (see
  /// `migrations.dart`).
  outboxVotesRebuilt('outbox_votes_v3');

  new(this.value);

  @override
  final String value;
}

/// The columns of the tables.
enum StoredColumn implements StableValue {
  /// The user whose session fetched a cached entry.
  owner('owner'),

  /// The period of a cached page.
  period('period'),

  /// The cursor of a cached page, written as JSON: `null` for the first page.
  cursorKey('cursor_key'),

  /// The size of a cached page.
  pageLimit('page_limit'),

  /// The meeting of a cached meeting, or of a vote.
  meetingId('meeting_id'),

  /// The document of a cached document.
  documentId('document_id'),

  /// Where the content of a cached document is: the location the repository
  /// handed out.
  location('location'),

  /// When an entry was cached.
  cachedAt('cached_at'),

  /// The page or the meeting as the cache writes it, as JSON.
  payload('payload'),

  /// The order of enqueueing: never reused, and the order the outbox is read
  /// in.
  sequence('sequence'),

  /// The key a vote is found by.
  idempotencyKey('idempotency_key'),

  /// Who voted.
  voterId('voter_id'),

  /// The resolution voted on.
  resolutionId('resolution_id'),

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

/// The indexes of the database.
enum StoredIndex implements StableValue {
  /// Finds the votes of a voter on a resolution.
  outboxByResolution('outbox_votes_by_voter_and_resolution'),

  /// Finds the entries that point at a file, to know whether another one still
  /// needs it.
  documentEntriesByLocation('document_entries_by_location');

  new(this.value);

  @override
  final String value;
}

/// The status of an entry of the outbox that no longer reads back as a vote,
/// kept as it is. It is a status of the table only: the domain knows a vote as
/// pending or rejected. Added by version 3 of the schema (see
/// `migrations.dart`).
const String outboxQuarantined = 'quarantined';
