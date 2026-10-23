import 'dart:convert';

import 'package:boardroom/app/persistence/boardroom_database.dart';
import 'package:boardroom/app/persistence/schema.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/types/cache_entry.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/domain/value_objects/page.dart';
import 'package:boardroom/core/infrastructure/persistence/guarded.dart';
import 'package:boardroom/core/infrastructure/persistence/stored_payload.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/infrastructure/stored_meeting.dart';
import 'package:drift/drift.dart';

/// What a stored entry is called in the logs.
enum _Stored implements StableValue {
  page('meetingPage'),
  meeting('meeting');

  new(this.value);

  @override
  final String value;
}

// The statements that read. A row is found by one column for each part of its
// key. The writes go through the tables of drift (`tables.dart`).
String get _pages => StoredTable.meetingPages.value;
String get _details => StoredTable.meetingDetails.value;
String get _owner => StoredColumn.owner.value;
String get _period => StoredColumn.period.value;
String get _cursorKey => StoredColumn.cursorKey.value;
String get _pageLimit => StoredColumn.pageLimit.value;
String get _meetingId => StoredColumn.meetingId.value;
String get _cachedAt => StoredColumn.cachedAt.value;
String get _payload => StoredColumn.payload.value;

String get _readPage =>
    'SELECT $_cachedAt, $_payload FROM $_pages '
    'WHERE $_owner = ? AND $_period = ? AND $_cursorKey = ? '
    'AND $_pageLimit = ?';
String get _readMeeting =>
    'SELECT $_cachedAt, $_payload FROM $_details '
    'WHERE $_owner = ? AND $_meetingId = ?';

/// The key of a page, one value for each column. The cursor is written as JSON
/// in its column (`null` is the first page, `"abc"` a cursor), which keeps "no
/// cursor" apart from any cursor.
typedef _PageKey = ({String owner, String period, String cursor, int limit});

_PageKey _pageKeyOf(UserId owner, MeetingPageKey key) => (
  owner: owner,
  period: key.period.value,
  cursor: jsonEncode(key.cursor),
  limit: key.limit,
);

/// The cache of meetings on SQLite, through drift. It keeps the pages and the
/// meetings of each owner as JSON in the format of its own
/// (`stored_meeting.dart`), not the one of the API, under a key made of one
/// column for each of its parts: the owner and the id (or the period, the
/// cursor and the size of the page) are never joined into one text, so two
/// different keys cannot share a row whatever characters they hold.
///
/// - A read checks what comes out of the database against its stored class and
///   the factories of the domain. A row that no longer passes (the format moved
///   on, the file was altered) is a miss: it is reported to the monitoring,
///   without its content, and deleted. It never throws.
/// - A save that fails removes the older entry of the key, so that it is not
///   served afterwards as if it were current; if that fails too, the error is
///   still the save's.
/// - `purge` empties both tables in one transaction.
/// - Every call settles: a statement that does not answer in time is a storage
///   error.
final class DriftMeetingCache implements MeetingCache {
  /// Creates the cache over [database]. [timeoutMillis] is how long a
  /// statement may take (`defaultStatementTimeoutMillis` by default).
  const new({
    required this.database,
    required this.monitoring,
    this.timeoutMillis,
  });

  /// The database the entries are in.
  final BoardroomDatabase database;

  /// Where a row that cannot be read is reported.
  final Monitoring monitoring;

  /// How long a statement may take.
  final int? timeoutMillis;

  int get _timeout => timeoutMillis ?? defaultStatementTimeoutMillis;

  @override
  Future<Result<void, StorageWriteFailedError>> savePage(
    UserId owner,
    MeetingPageKey key,
    Page<MeetingSummary> page,
    Instant cachedAt,
  ) {
    final row = _pageKeyOf(owner, key);
    return _save(
      () => database
          .into(database.meetingPages)
          .insert(
            MeetingPagesCompanion.insert(
              owner: row.owner,
              period: row.period,
              cursorKey: row.cursor,
              pageLimit: row.limit,
              cachedAt: cachedAt,
              payload: jsonEncode(storedPageOf(page).toJson()),
            ),
            mode: InsertMode.insertOrReplace,
          ),
      () => _deletePage(row),
    );
  }

  @override
  Future<Result<CacheEntry<Page<MeetingSummary>>?, StorageReadFailedError>>
  readPage(UserId owner, MeetingPageKey key) {
    final row = _pageKeyOf(owner, key);
    return _read<Page<MeetingSummary>>(
      _Stored.page,
      _readPage,
      [
        Variable.withString(row.owner),
        Variable.withString(row.period),
        Variable.withString(row.cursor),
        Variable.withInt(row.limit),
      ],
      () => _deletePage(row),
      (payload) => decodePayload(payload, StoredMeetingPage.fromJson, pageOf),
    );
  }

  @override
  Future<Result<void, StorageWriteFailedError>> removePage(
    UserId owner,
    MeetingPageKey key,
  ) {
    final row = _pageKeyOf(owner, key);
    return guardedWrite(() => _deletePage(row), _timeout);
  }

  @override
  Future<Result<void, StorageWriteFailedError>> saveMeeting(
    UserId owner,
    Meeting meeting,
    Instant cachedAt,
  ) => _save(
    () => database
        .into(database.meetingDetails)
        .insert(
          MeetingDetailsCompanion.insert(
            owner: owner,
            meetingId: meeting.id,
            cachedAt: cachedAt,
            payload: jsonEncode(storedMeetingOf(meeting).toJson()),
          ),
          mode: InsertMode.insertOrReplace,
        ),
    () => _deleteMeeting(owner, meeting.id),
  );

  @override
  Future<Result<CacheEntry<Meeting>?, StorageReadFailedError>> readMeeting(
    UserId owner,
    MeetingId id,
  ) => _read<Meeting>(
    _Stored.meeting,
    _readMeeting,
    [Variable.withString(owner), Variable.withString(id)],
    () => _deleteMeeting(owner, id),
    (payload) => decodePayload(payload, StoredMeeting.fromJson, meetingOf),
  );

  @override
  Future<Result<void, StorageWriteFailedError>> removeMeeting(
    UserId owner,
    MeetingId id,
  ) => guardedWrite(() => _deleteMeeting(owner, id), _timeout);

  @override
  Future<Result<void, StorageWriteFailedError>> purge() => guardedWrite(
    () => database.transaction(() async {
      await database.delete(database.meetingPages).go();
      await database.delete(database.meetingDetails).go();
    }),
    _timeout,
  );

  Future<void> _deletePage(_PageKey row) async {
    await (database.delete(database.meetingPages)..where(
          (page) =>
              page.owner.equals(row.owner) &
              page.period.equals(row.period) &
              page.cursorKey.equals(row.cursor) &
              page.pageLimit.equals(row.limit),
        ))
        .go();
  }

  Future<void> _deleteMeeting(UserId owner, MeetingId id) async {
    await (database.delete(database.meetingDetails)..where(
          (meeting) =>
              meeting.owner.equals(owner) & meeting.meetingId.equals(id),
        ))
        .go();
  }

  Future<Result<void, StorageWriteFailedError>> _save(
    Future<void> Function() write,
    Future<void> Function() removal,
  ) async {
    final saved = await guardedWrite(write, _timeout);
    switch (saved) {
      case Ok():
        return ok<void>(null);
      case Err(:final error):
        // The entry that was there is older than the one that could not be
        // written: do not leave it to be read as if it were current. Best
        // effort, the caller gets the failure of the save.
        await guardedWrite(removal, _timeout);
        return err(error);
    }
  }

  Future<Result<CacheEntry<T>?, StorageReadFailedError>> _read<T>(
    _Stored resource,
    String statement,
    List<Variable<Object>> keyParams,
    Future<void> Function() removal,
    Result<T, Unreadable> Function(String payload) decode,
  ) async {
    final selected = await guardedRead(
      () => database.customSelect(statement, variables: keyParams).get(),
      _timeout,
    );
    final List<QueryRow> rows;
    switch (selected) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        rows = value;
    }
    if (rows.isEmpty) {
      return ok<CacheEntry<T>?>(null);
    }

    final data = rows.first.data;
    final payload = data[_payload];
    final cachedAt = instantOf(data[_cachedAt]);
    final decoded = payload is String ? decode(payload) : null;
    if (decoded case Ok(:final value) when cachedAt != null) {
      return ok<CacheEntry<T>?>(CacheEntry(value: value, cachedAt: cachedAt));
    }

    final issuePaths = switch (decoded) {
      Err(:final error) => error.issuePaths,
      _ => null,
    };
    monitoring.captureError(
      MonitoringEvent.storedRowDiscarded,
      storageReadFailed(unreadableEntryCause),
      {
        LogAttribute.resource: resource.value,
        LogAttribute.issuePaths: ?issuePaths,
      },
    );
    // Best effort: a row that cannot be read is a miss whether or not it can
    // be deleted.
    await guardedWrite(removal, _timeout);
    return ok<CacheEntry<T>?>(null);
  }
}
