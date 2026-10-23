import 'dart:convert';

import 'package:boardroom/app/persistence/boardroom_database.dart';
import 'package:boardroom/app/persistence/schema.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/types/cache_entry.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/core/infrastructure/persistence/guarded.dart';
import 'package:boardroom/core/infrastructure/persistence/stored_payload.dart';
import 'package:boardroom/core/infrastructure/shared/serial_queue.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:boardroom/features/documents/infrastructure/document_content.dart';
import 'package:boardroom/features/documents/infrastructure/stored_document.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

/// What a stored entry is called in the logs.
const String _resource = 'document';

// The statements that read. A row is found by one column for each part of its
// key. The writes go through the tables of drift (`tables.dart`).
String get _entries => StoredTable.documentEntries.value;
String get _owner => StoredColumn.owner.value;
String get _documentId => StoredColumn.documentId.value;
String get _cachedAt => StoredColumn.cachedAt.value;
String get _location => StoredColumn.location.value;
String get _payload => StoredColumn.payload.value;

String get _key => '$_owner = ? AND $_documentId = ?';
String get _read =>
    'SELECT $_cachedAt, $_location, $_payload FROM $_entries WHERE $_key';
String get _locationOf => 'SELECT $_location FROM $_entries WHERE $_key';
String get _others =>
    'SELECT count(*) AS others FROM $_entries '
    'WHERE $_location = ? AND NOT ($_key)';
String get _allLocations => 'SELECT DISTINCT $_location FROM $_entries';

/// The name of the count the statement of [_others] answers.
const String _othersColumn = 'others';

/// What a step that touches the files answers with: a value, or the failure of
/// the file system.
typedef _Step<T> = Result<T, FileStoreFailure>;

/// What [DriftDocumentCache] needs.
@immutable
final class DriftDocumentCacheOptions {
  /// Creates the options. [timeoutMillis] is how long a statement or a file
  /// operation may take (`defaultStatementTimeoutMillis` by default).
  const new({
    required this.database,
    required this.files,
    required this.monitoring,
    this.timeoutMillis,
  });

  /// The database the entries are in.
  final BoardroomDatabase database;

  /// Where the content of the documents is. The cache looks at it and deletes
  /// from it; it never writes to it, the repositories do.
  final FileStore files;

  /// Where a row that cannot be read is reported.
  final Monitoring monitoring;

  /// How long a statement or a file operation may take.
  final int? timeoutMillis;
}

/// A row read back: the document with the location of its content, and when it
/// was cached.
typedef _Decoded = ({ViewableDocument viewable, Instant cachedAt});

/// The cache of the documents already viewed, on SQLite (through drift) for the
/// metadata and in the files of the device for the content. It keeps, for each
/// owner and document, the metadata as JSON in the format of its own
/// (`stored_document.dart`), the instant and the location of the content, under
/// a key made of one column for each part (the owner and the id are never
/// joined in a text, so two different keys cannot share a row whatever
/// characters they hold).
///
/// - **The content is deleted before the entry.** `remove`, `purge` and a
///   `save` that moves an entry to another file delete the file first, and only
///   then drop the row; if the file cannot be deleted the call fails and the
///   row stays, so that it can be tried again. An entry is never dropped while
///   its file is left behind with nothing pointing at it.
/// - **Files are shared by count.** Two owners may point at the same file. The
///   file is deleted only when no other row points at it (the index on the
///   location answers), so one user signing out cannot take the file from
///   another.
/// - **An entry whose content is gone is a miss** (the system emptied the
///   caches, the file was deleted): the row is dropped, since the next request
///   refills it.
/// - **A row that no longer reads back is a miss** (the format moved on, the
///   file was altered, the location is no file of the store). It is reported to
///   the monitoring, without its content, left out of the answer, and removed
///   together with its file. It never throws.
/// - **Files that no row points at** (a download whose entry was never saved,
///   a deletion that was interrupted, a partial file) are swept when the cache
///   starts ([sweepOrphans]).
/// - A save that fails removes the older entry of its key, whatever its file
///   does, so that it is not served afterwards as if it were current.
/// - Calls run one at a time, in the order they were made: a call reads,
///   decides and writes in several steps (a row, then a file, then a row), and
///   two callers must not interleave them.
/// - Every call settles: a statement or a file operation that does not answer
///   in time is a storage error.
final class DriftDocumentCache implements DocumentCache {
  /// Creates the cache.
  new(DriftDocumentCacheOptions options)
    : _database = options.database,
      _files = options.files,
      _monitoring = options.monitoring,
      _timeout = options.timeoutMillis ?? defaultStatementTimeoutMillis;

  final BoardroomDatabase _database;
  final FileStore _files;
  final Monitoring _monitoring;
  final int _timeout;
  final SerialQueue _inOrder = createSerialQueue();

  @override
  Future<Result<void, StorageWriteFailedError>> save(
    UserId owner,
    ViewableDocument viewable,
    Instant cachedAt,
  ) => _inOrder(() async {
    final saved = await _write(() => _upsert(owner, viewable, cachedAt));
    if (saved is Ok) {
      return saved;
    }
    // The entry that was there is older than the one that could not be
    // written: do not leave it to be read as if it were current, whatever
    // happens to its file. Best effort, the caller gets the failure of the
    // save.
    await _write(() => _forget(owner, viewable.document.id));
    return saved;
  });

  @override
  Future<Result<CacheEntry<ViewableDocument>?, StorageReadFailedError>> read(
    UserId owner,
    DocumentId id,
  ) => _inOrder(() async {
    final done = await attemptOnDatabase(() => _lookup(owner, id), _timeout);
    switch (done) {
      case Err(:final error):
        return err(storageReadFailed(error.cause));
      case Ok(value: Err(:final error)):
        return err(storageReadFailed(error.cause));
      case Ok(value: Ok(:final value)):
        return ok(value);
    }
  });

  @override
  Future<Result<void, StorageWriteFailedError>> remove(
    UserId owner,
    DocumentId id,
  ) => _inOrder(() => _write(() => _removeEntry(owner, id)));

  @override
  Future<Result<void, StorageWriteFailedError>> purge() =>
      _inOrder(() => _write(_removeEverything));

  /// Deletes the files of the documents that no entry points at: what a
  /// download left when its entry was never saved, what a deletion that was
  /// interrupted left, a file that was being written when the app stopped. It
  /// runs when the cache starts, before any download, so no file it finds can
  /// be one that is about to be saved. A file that cannot be deleted is left
  /// for the next start; the others are still deleted. Fails when the files or
  /// the database cannot be read, or a file is left: the caller reports the
  /// failure, once, whatever its cause.
  Future<Result<void, StorageWriteFailedError>> sweepOrphans() =>
      _inOrder(() => _write(_sweep));

  /// A write: the database and the files, in bounded time, with the failure of
  /// whichever fails.
  Future<Result<void, StorageWriteFailedError>> _write(
    Future<_Step<void>> Function() work,
  ) async {
    final done = await attemptOnDatabase(work, _timeout);
    switch (done) {
      case Err(:final error):
        return err(storageWriteFailed(error.cause));
      case Ok(value: Err(:final error)):
        return err(storageWriteFailed(error.cause));
      case Ok():
        return ok<void>(null);
    }
  }

  Future<_Step<void>> _upsert(
    UserId owner,
    ViewableDocument viewable,
    Instant cachedAt,
  ) async {
    final ViewableDocument(:document, :location) = viewable;
    // An entry that moves to another file leaves its previous one behind,
    // unless another entry still points at it: nothing may stay on the device
    // with nothing pointing at it.
    final previous = await _locationOfEntry(owner, document.id);
    if (previous != null && previous != location) {
      final released = await _releaseContent(previous, owner, document.id);
      if (released is Err) {
        return released;
      }
    }
    await _database
        .into(_database.documentEntries)
        .insert(
          DocumentEntriesCompanion.insert(
            owner: owner,
            documentId: document.id,
            cachedAt: cachedAt,
            location: location,
            payload: jsonEncode(storedDocumentOf(document).toJson()),
          ),
          mode: InsertMode.insertOrReplace,
        );
    return ok<void>(null);
  }

  /// Drops an entry, and its file as far as it can: for an entry that must not
  /// be served any more.
  Future<_Step<void>> _forget(UserId owner, DocumentId id) async {
    final location = await _locationOfEntry(owner, id);
    if (location == null) {
      return ok<void>(null);
    }
    await _releaseContent(location, owner, id);
    await _deleteEntry(owner, id);
    return ok<void>(null);
  }

  Future<_Step<void>> _removeEntry(UserId owner, DocumentId id) async {
    final location = await _locationOfEntry(owner, id);
    if (location == null) {
      return ok<void>(null);
    }
    final released = await _releaseContent(location, owner, id);
    if (released is Err) {
      return released;
    }
    await _deleteEntry(owner, id);
    return ok<void>(null);
  }

  Future<_Step<void>> _removeEverything() async {
    final rows = await _database.customSelect(_allLocations).get();

    // The content first, every file that can be deleted: the entries of the
    // ones that went follow, those of the ones that did not stay, so that the
    // call can be repeated.
    FileStoreFailure? failure;
    final deleted = <String>[];
    for (final row in rows) {
      final location = '${row.data[_location]}';
      final result = switch (parseDocumentLocation(location)) {
        Ok(:final value) => await deleteContent(_files, value),
        Err() => ok<void>(null),
      };
      switch (result) {
        case Ok():
          deleted.add(location);
        case Err(:final error):
          failure ??= error;
      }
    }
    await _database.transaction(() async {
      for (final location in deleted) {
        await (_database.delete(
          _database.documentEntries,
        )..where((entry) => entry.location.equals(location))).go();
      }
    });
    if (failure != null) {
      return err(failure);
    }

    await _database.delete(_database.documentEntries).go();
    // What no entry points at goes too: purging leaves nothing of any document
    // on the device.
    return await _files.deleteAll();
  }

  Future<_Step<void>> _sweep() async {
    final listed = await _files.list();
    final List<String> names;
    switch (listed) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        names = value;
    }

    final referenced = {
      for (final row in await _database.customSelect(_allLocations).get())
        if (parseDocumentLocation('${row.data[_location]}') case Ok(
          :final value,
        ))
          _files.nameOf(value),
    };
    FileStoreFailure? failure;
    for (final name in names) {
      if (referenced.contains(name)) {
        continue;
      }
      if (await _files.delete(name) case Err(:final error)) {
        failure ??= error;
      }
    }
    if (failure != null) {
      return err(failure);
    }
    return ok<void>(null);
  }

  /// The location an entry points at, or `null` when there is no entry.
  Future<String?> _locationOfEntry(UserId owner, DocumentId id) async {
    final rows = await _database
        .customSelect(
          _locationOf,
          variables: [Variable.withString(owner), Variable.withString(id)],
        )
        .get();
    final location = rows.firstOrNull?.data[_location];
    return location is String ? location : null;
  }

  Future<void> _deleteEntry(UserId owner, DocumentId id) async {
    await (_database.delete(_database.documentEntries)..where(
          (entry) => entry.owner.equals(owner) & entry.documentId.equals(id),
        ))
        .go();
  }

  /// Deletes the file of the entry `(owner, id)`, unless another entry points
  /// at it. A location that is no file of the store has nothing to delete.
  Future<_Step<void>> _releaseContent(
    String location,
    UserId owner,
    DocumentId id,
  ) async {
    final rows = await _database
        .customSelect(
          _others,
          variables: [
            Variable.withString(location),
            Variable.withString(owner),
            Variable.withString(id),
          ],
        )
        .get();
    final others = rows.firstOrNull?.data[_othersColumn];
    if (others is num && others > 0) {
      return ok<void>(null);
    }
    return switch (parseDocumentLocation(location)) {
      Ok(:final value) => await deleteContent(_files, value),
      Err() => ok<void>(null),
    };
  }

  Future<_Step<CacheEntry<ViewableDocument>?>> _lookup(
    UserId owner,
    DocumentId id,
  ) async {
    final rows = await _database
        .customSelect(
          _read,
          variables: [Variable.withString(owner), Variable.withString(id)],
        )
        .get();
    if (rows.isEmpty) {
      return ok<CacheEntry<ViewableDocument>?>(null);
    }

    final row = rows.first.data;
    final _Decoded decoded;
    switch (_decode(row)) {
      case Err(:final error):
        await _discard(owner, id, row, error.issuePaths);
        return ok<CacheEntry<ViewableDocument>?>(null);
      case Ok(:final value):
        decoded = value;
    }

    final location = decoded.viewable.location;
    final present = await contentExists(_files, location);
    switch (present) {
      case Err(:final error):
        return err(error);
      case Ok(value: false):
        // The content is gone: the entry points at nothing. Dropped, unless a
        // newer save has moved it.
        await _bestEffort(() => _deleteEntryWhileAt(owner, id, location));
        return ok<CacheEntry<ViewableDocument>?>(null);
      case Ok():
        return ok<CacheEntry<ViewableDocument>?>(
          CacheEntry(value: decoded.viewable, cachedAt: decoded.cachedAt),
        );
    }
  }

  /// Removes an entry only while it still points where it was read to: a newer
  /// save is left alone.
  Future<void> _deleteEntryWhileAt(
    UserId owner,
    DocumentId id,
    DocumentLocation location,
  ) async {
    await (_database.delete(_database.documentEntries)..where(
          (entry) =>
              entry.owner.equals(owner) &
              entry.documentId.equals(id) &
              entry.location.equals(location),
        ))
        .go();
  }

  /// A row read back: it is JSON of the shape stored, its values pass the
  /// domain, its file is one of the store.
  Result<_Decoded, Unreadable> _decode(Map<String, Object?> row) {
    final payload = row[_payload];
    final cachedAt = instantOf(row[_cachedAt]);
    final location = switch (parseDocumentLocation('${row[_location]}')) {
      Ok(:final value) => value,
      Err() => null,
    };
    if (payload is! String ||
        cachedAt == null ||
        location == null ||
        _files.nameOf(location) == null) {
      return err(const Unreadable());
    }
    return switch (decodePayload(
      payload,
      StoredDocument.fromJson,
      documentOf,
    )) {
      Ok(:final value) => ok((
        viewable: ViewableDocument(document: value, location: location),
        cachedAt: cachedAt,
      )),
      Err(:final error) => err(error),
    };
  }

  /// Reports a row that cannot be read, and removes it with its file. Best
  /// effort: it is a miss either way.
  Future<void> _discard(
    UserId owner,
    DocumentId id,
    Map<String, Object?> row,
    String? issuePaths,
  ) async {
    _monitoring.captureError(
      MonitoringEvent.storedRowDiscarded,
      storageReadFailed(unreadableEntryCause),
      {LogAttribute.resource: _resource, LogAttribute.issuePaths: ?issuePaths},
    );
    await _bestEffort(() async {
      await _releaseContent('${row[_location]}', owner, id);
      await _deleteEntry(owner, id);
    });
  }

  Future<void> _bestEffort(Future<void> Function() work) async {
    await attemptOnDatabase(work, _timeout);
  }
}
