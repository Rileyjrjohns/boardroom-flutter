import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/infrastructure/persistence/schema.dart';
import 'package:meta/meta.dart';

/// A step from one version of the schema to the next. Versions are 1, 2, 3, ...
/// with no gap. The statements run in one transaction together with the update
/// of the version, so that a migration that fails leaves the database at the
/// version it was at.
///
/// Forward only: a migration that was released is never edited, a change is a
/// new migration, and there is no way back. A database that is more recent than
/// the app (the app was downgraded) is refused, not touched (see
/// `migrate.dart`).
@immutable
final class Migration {
  /// Creates the step that brings the schema to [version].
  const new({required this.version, required this.statements});

  /// The version of the schema once the statements have run.
  final int version;

  /// The statements, in order.
  final List<String> statements;
}

String get _pending => "'${OutboxStatus.pending.value}'";
String get _rejected => "'${OutboxStatus.rejected.value}'";
const String _quarantined = "'$outboxQuarantined'";

String get _meetingPages => StoredTable.meetingPages.value;
String get _meetingDetails => StoredTable.meetingDetails.value;
String get _documentEntries => StoredTable.documentEntries.value;
String get _outboxVotes => StoredTable.outboxVotes.value;
String get _outboxVotesRebuilt => StoredTable.outboxVotesRebuilt.value;
String get _outboxByResolution => StoredIndex.outboxByResolution.value;
String get _entriesByLocation => StoredIndex.documentEntriesByLocation.value;

String get _owner => StoredColumn.owner.value;
String get _period => StoredColumn.period.value;
String get _cursorKey => StoredColumn.cursorKey.value;
String get _pageLimit => StoredColumn.pageLimit.value;
String get _meetingId => StoredColumn.meetingId.value;
String get _documentId => StoredColumn.documentId.value;
String get _location => StoredColumn.location.value;
String get _cachedAt => StoredColumn.cachedAt.value;
String get _payload => StoredColumn.payload.value;
String get _sequence => StoredColumn.sequence.value;
String get _idempotencyKey => StoredColumn.idempotencyKey.value;
String get _voterId => StoredColumn.voterId.value;
String get _resolutionId => StoredColumn.resolutionId.value;
String get _choice => StoredColumn.choice.value;
String get _castAt => StoredColumn.castAt.value;
String get _enqueuedAt => StoredColumn.enqueuedAt.value;
String get _attempts => StoredColumn.attempts.value;
String get _status => StoredColumn.status.value;
String get _rejectionReason => StoredColumn.rejectionReason.value;
String get _rejectedAt => StoredColumn.rejectedAt.value;

/// Version 1: the cache of meetings and the outbox of votes.
///
/// The cache keeps what it is given as the API writes it (JSON). Its key is
/// made of one column for each part (the owner, the period, the cursor, the
/// size of the page, the id of the meeting), never of the parts joined in one
/// text, so that two different keys can never be the same row, whatever
/// characters the owner or the id contain. The outbox holds a vote in columns,
/// in the order it was enqueued: `sequence` only grows, and a row that is
/// deleted never gives its number back.
Migration get _initial => Migration(
  version: 1,
  statements: [
    '''
CREATE TABLE $_meetingPages (
  $_owner TEXT NOT NULL,
  $_period TEXT NOT NULL,
  $_cursorKey TEXT NOT NULL,
  $_pageLimit INTEGER NOT NULL,
  $_cachedAt INTEGER NOT NULL,
  $_payload TEXT NOT NULL,
  PRIMARY KEY ($_owner, $_period, $_cursorKey, $_pageLimit)
) WITHOUT ROWID''',
    '''
CREATE TABLE $_meetingDetails (
  $_owner TEXT NOT NULL,
  $_meetingId TEXT NOT NULL,
  $_cachedAt INTEGER NOT NULL,
  $_payload TEXT NOT NULL,
  PRIMARY KEY ($_owner, $_meetingId)
) WITHOUT ROWID''',
    '''
CREATE TABLE $_outboxVotes (
  $_sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  $_idempotencyKey TEXT NOT NULL UNIQUE,
  $_voterId TEXT NOT NULL,
  $_resolutionId TEXT NOT NULL,
  $_meetingId TEXT NOT NULL,
  $_choice TEXT NOT NULL,
  $_castAt INTEGER NOT NULL,
  $_enqueuedAt INTEGER NOT NULL,
  $_attempts INTEGER NOT NULL,
  $_status TEXT NOT NULL CHECK ($_status IN ($_pending, $_rejected)),
  $_rejectionReason TEXT,
  $_rejectedAt INTEGER,
  CHECK (($_status = $_pending) = ($_rejectionReason IS NULL)),
  CHECK (($_status = $_pending) = ($_rejectedAt IS NULL))
)''',
  ],
);

/// Version 2: finds the votes of a voter on a resolution without reading the
/// whole outbox. Version 1 answers `findByResolution` with a scan, which is
/// fine for the first votes and not for a board that votes for years without
/// acknowledging the rejected ones. It is a migration of its own from the
/// start, so that the path from an older database to the latest one exists, and
/// is tested, before the first change of the schema that cannot wait.
Migration get _indexOutboxByResolution => Migration(
  version: 2,
  statements: [
    '''
CREATE INDEX $_outboxByResolution
  ON $_outboxVotes ($_voterId, $_resolutionId)''',
  ],
);

/// Version 3: an entry of the outbox that no longer reads back as a vote can be
/// kept, as it is, out of the queue (status `quarantined`), instead of being
/// deleted. SQLite cannot change a `CHECK`, so the table is made again, with
/// the same columns:
///
/// - the status admits `quarantined`, and only for that status are the reason
///   and the instant of a rejection not constrained (what is in an entry that
///   cannot be read is whatever it is);
/// - the rows are copied with their `sequence`, and the high-water mark of the
///   sequence is carried over, so that a number that was given to a vote and
///   then freed is still never given again;
/// - the index of version 2 is created again, since dropping the table dropped
///   it.
///
/// Every vote of an existing database is a row of the new table, as it was.
Migration get _quarantineUnreadableVotes => Migration(
  version: 3,
  statements: [
    '''
CREATE TABLE $_outboxVotesRebuilt (
  $_sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  $_idempotencyKey TEXT NOT NULL UNIQUE,
  $_voterId TEXT NOT NULL,
  $_resolutionId TEXT NOT NULL,
  $_meetingId TEXT NOT NULL,
  $_choice TEXT NOT NULL,
  $_castAt INTEGER NOT NULL,
  $_enqueuedAt INTEGER NOT NULL,
  $_attempts INTEGER NOT NULL,
  $_status TEXT NOT NULL
    CHECK ($_status IN ($_pending, $_rejected, $_quarantined)),
  $_rejectionReason TEXT,
  $_rejectedAt INTEGER,
  CHECK ($_status = $_quarantined
    OR (($_status = $_pending) = ($_rejectionReason IS NULL))),
  CHECK ($_status = $_quarantined
    OR (($_status = $_pending) = ($_rejectedAt IS NULL)))
)''',
    '''
INSERT INTO $_outboxVotesRebuilt
  ($_sequence, $_idempotencyKey, $_voterId, $_resolutionId,
   $_meetingId, $_choice, $_castAt, $_enqueuedAt,
   $_attempts, $_status, $_rejectionReason, $_rejectedAt)
  SELECT $_sequence, $_idempotencyKey, $_voterId, $_resolutionId,
   $_meetingId, $_choice, $_castAt, $_enqueuedAt,
   $_attempts, $_status, $_rejectionReason, $_rejectedAt
  FROM $_outboxVotes''',
    "DELETE FROM sqlite_sequence WHERE name = '$_outboxVotesRebuilt'",
    '''
INSERT INTO sqlite_sequence (name, seq)
  SELECT '$_outboxVotesRebuilt', seq FROM sqlite_sequence
  WHERE name = '$_outboxVotes'
''',
    'DROP TABLE $_outboxVotes',
    'ALTER TABLE $_outboxVotesRebuilt RENAME TO $_outboxVotes',
    '''
CREATE INDEX $_outboxByResolution
  ON $_outboxVotes ($_voterId, $_resolutionId)''',
  ],
);

/// Version 4: the cache of the documents already viewed. An entry is the
/// metadata of a document and where its content is (a file, kept apart from the
/// database), for one owner.
///
/// - The key is one column for each part, `(owner, document_id)`, never the two
///   joined in a text, as in the cache of meetings.
/// - The location is a column of its own and not a part of the payload, because
///   the cache has to ask the database which entries point at a file: the file
///   of an entry is deleted only when no other entry (another owner's) needs
///   it. The index answers that without reading every row.
/// - The payload is the document as the cache stores it, in the format of the
///   cache (see `stored_document.dart`).
Migration get _cacheDocuments => Migration(
  version: 4,
  statements: [
    '''
CREATE TABLE $_documentEntries (
  $_owner TEXT NOT NULL,
  $_documentId TEXT NOT NULL,
  $_cachedAt INTEGER NOT NULL,
  $_location TEXT NOT NULL,
  $_payload TEXT NOT NULL,
  PRIMARY KEY ($_owner, $_documentId)
) WITHOUT ROWID''',
    '''
CREATE INDEX $_entriesByLocation
  ON $_documentEntries ($_location)''',
  ],
);

/// Every migration of the database, in order. The last one is the version the
/// app expects.
final List<Migration> migrations = List.unmodifiable([
  _initial,
  _indexOutboxByResolution,
  _quarantineUnreadableVotes,
  _cacheDocuments,
]);
