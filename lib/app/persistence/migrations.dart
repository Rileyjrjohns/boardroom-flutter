import 'package:boardroom/core/infrastructure/persistence/migrate.dart';
import 'package:boardroom/features/documents/infrastructure/persistence/schema.dart';
import 'package:boardroom/features/meetings/infrastructure/persistence/schema.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/infrastructure/persistence/schema.dart';

// The history of the file: the migrations of the database of the whole app, in
// order. Each feature owns its tables and their names (`schema.dart` of its
// `infrastructure/persistence` folder), and this list, which is the app's, reads
// them; the machinery that runs the list is `migrate.dart` of the core.

String get _pending => "'${OutboxStatus.pending.value}'";
String get _rejected => "'${OutboxStatus.rejected.value}'";
const String _quarantined = "'$outboxQuarantined'";

String get _meetingPages => MeetingStoredTable.meetingPages.value;
String get _meetingDetails => MeetingStoredTable.meetingDetails.value;
String get _documentEntries => DocumentStoredTable.documentEntries.value;
String get _outboxVotes => VoteStoredTable.outboxVotes.value;
String get _outboxVotesRebuilt => VoteStoredTable.outboxVotesRebuilt.value;
String get _outboxByResolution => VoteStoredIndex.outboxByResolution.value;
String get _entriesByLocation =>
    DocumentStoredIndex.documentEntriesByLocation.value;

String get _mOwner => MeetingStoredColumn.owner.value;
String get _mPeriod => MeetingStoredColumn.period.value;
String get _mCursorKey => MeetingStoredColumn.cursorKey.value;
String get _mPageLimit => MeetingStoredColumn.pageLimit.value;
String get _mMeetingId => MeetingStoredColumn.meetingId.value;
String get _mCachedAt => MeetingStoredColumn.cachedAt.value;
String get _mPayload => MeetingStoredColumn.payload.value;

String get _dOwner => DocumentStoredColumn.owner.value;
String get _dDocumentId => DocumentStoredColumn.documentId.value;
String get _dLocation => DocumentStoredColumn.location.value;
String get _dCachedAt => DocumentStoredColumn.cachedAt.value;
String get _dPayload => DocumentStoredColumn.payload.value;

String get _vSequence => VoteStoredColumn.sequence.value;
String get _vIdempotencyKey => VoteStoredColumn.idempotencyKey.value;
String get _vVoterId => VoteStoredColumn.voterId.value;
String get _vResolutionId => VoteStoredColumn.resolutionId.value;
String get _vMeetingId => VoteStoredColumn.meetingId.value;
String get _vChoice => VoteStoredColumn.choice.value;
String get _vCastAt => VoteStoredColumn.castAt.value;
String get _vEnqueuedAt => VoteStoredColumn.enqueuedAt.value;
String get _vAttempts => VoteStoredColumn.attempts.value;
String get _vStatus => VoteStoredColumn.status.value;
String get _vRejectionReason => VoteStoredColumn.rejectionReason.value;
String get _vRejectedAt => VoteStoredColumn.rejectedAt.value;

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
  $_mOwner TEXT NOT NULL,
  $_mPeriod TEXT NOT NULL,
  $_mCursorKey TEXT NOT NULL,
  $_mPageLimit INTEGER NOT NULL,
  $_mCachedAt INTEGER NOT NULL,
  $_mPayload TEXT NOT NULL,
  PRIMARY KEY ($_mOwner, $_mPeriod, $_mCursorKey, $_mPageLimit)
) WITHOUT ROWID''',
    '''
CREATE TABLE $_meetingDetails (
  $_mOwner TEXT NOT NULL,
  $_mMeetingId TEXT NOT NULL,
  $_mCachedAt INTEGER NOT NULL,
  $_mPayload TEXT NOT NULL,
  PRIMARY KEY ($_mOwner, $_mMeetingId)
) WITHOUT ROWID''',
    '''
CREATE TABLE $_outboxVotes (
  $_vSequence INTEGER PRIMARY KEY AUTOINCREMENT,
  $_vIdempotencyKey TEXT NOT NULL UNIQUE,
  $_vVoterId TEXT NOT NULL,
  $_vResolutionId TEXT NOT NULL,
  $_vMeetingId TEXT NOT NULL,
  $_vChoice TEXT NOT NULL,
  $_vCastAt INTEGER NOT NULL,
  $_vEnqueuedAt INTEGER NOT NULL,
  $_vAttempts INTEGER NOT NULL,
  $_vStatus TEXT NOT NULL CHECK ($_vStatus IN ($_pending, $_rejected)),
  $_vRejectionReason TEXT,
  $_vRejectedAt INTEGER,
  CHECK (($_vStatus = $_pending) = ($_vRejectionReason IS NULL)),
  CHECK (($_vStatus = $_pending) = ($_vRejectedAt IS NULL))
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
  ON $_outboxVotes ($_vVoterId, $_vResolutionId)''',
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
  $_vSequence INTEGER PRIMARY KEY AUTOINCREMENT,
  $_vIdempotencyKey TEXT NOT NULL UNIQUE,
  $_vVoterId TEXT NOT NULL,
  $_vResolutionId TEXT NOT NULL,
  $_vMeetingId TEXT NOT NULL,
  $_vChoice TEXT NOT NULL,
  $_vCastAt INTEGER NOT NULL,
  $_vEnqueuedAt INTEGER NOT NULL,
  $_vAttempts INTEGER NOT NULL,
  $_vStatus TEXT NOT NULL
    CHECK ($_vStatus IN ($_pending, $_rejected, $_quarantined)),
  $_vRejectionReason TEXT,
  $_vRejectedAt INTEGER,
  CHECK ($_vStatus = $_quarantined
    OR (($_vStatus = $_pending) = ($_vRejectionReason IS NULL))),
  CHECK ($_vStatus = $_quarantined
    OR (($_vStatus = $_pending) = ($_vRejectedAt IS NULL)))
)''',
    '''
INSERT INTO $_outboxVotesRebuilt
  ($_vSequence, $_vIdempotencyKey, $_vVoterId, $_vResolutionId,
   $_vMeetingId, $_vChoice, $_vCastAt, $_vEnqueuedAt,
   $_vAttempts, $_vStatus, $_vRejectionReason, $_vRejectedAt)
  SELECT $_vSequence, $_vIdempotencyKey, $_vVoterId, $_vResolutionId,
   $_vMeetingId, $_vChoice, $_vCastAt, $_vEnqueuedAt,
   $_vAttempts, $_vStatus, $_vRejectionReason, $_vRejectedAt
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
  ON $_outboxVotes ($_vVoterId, $_vResolutionId)''',
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
  $_dOwner TEXT NOT NULL,
  $_dDocumentId TEXT NOT NULL,
  $_dCachedAt INTEGER NOT NULL,
  $_dLocation TEXT NOT NULL,
  $_dPayload TEXT NOT NULL,
  PRIMARY KEY ($_dOwner, $_dDocumentId)
) WITHOUT ROWID''',
    '''
CREATE INDEX $_entriesByLocation
  ON $_documentEntries ($_dLocation)''',
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
