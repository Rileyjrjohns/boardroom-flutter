import 'dart:convert';

import 'package:boardroom/core/application/ports/types/cache_entry.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/core/infrastructure/shared/serial_queue.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:boardroom/features/documents/infrastructure/document_content.dart';

/// A document cache whose entries are in memory and whose content is on the
/// device, in the files of the store: the cache of the mock configuration,
/// which has no database. It keeps the metadata and the location of each
/// document per owner, and answers for the content through the files: an entry
/// whose content is gone is a miss, and dropping an entry deletes its content,
/// first, so that a file that cannot be deleted keeps its entry and the call
/// fails instead of reporting a deletion that did not happen. Two owners may
/// point at the same file; it is deleted only when the last entry that points
/// at it is dropped, so one user signing out cannot take the file from another.
///
/// The entries die with the app and the files do not, so the composition root
/// empties the store when it starts (`FileStore.deleteAll`): nothing may stay
/// on the device with nothing pointing at it. Calls run one at a time, in the
/// order they were made.
final class InMemoryDocumentCache implements DocumentCache {
  /// Creates a cache whose content is in `files`.
  new(this._files);

  final FileStore _files;
  final Map<String, CacheEntry<ViewableDocument>> _entries = {};
  final SerialQueue _inOrder = createSerialQueue();
  StorageWriteFailedError? _writeFailure;

  /// Makes every save fail with this error while set, as a full disk would. A
  /// save that fails drops the older entry for the same owner and document, as
  /// the port requires. For tests.
  // ignore: use_setters_to_change_properties
  void failWritesWith(StorageWriteFailedError? failure) {
    _writeFailure = failure;
  }

  @override
  Future<Result<void, StorageWriteFailedError>> save(
    UserId owner,
    ViewableDocument viewable,
    Instant cachedAt,
  ) => _inOrder(() async {
    final key = _entryKey(owner, viewable.document.id);
    if (_writeFailure case final failure?) {
      await _drop(key);
      return err(failure);
    }
    // An entry that moves to another location leaves its previous content
    // behind, unless another entry still points at it: nothing may stay on the
    // device with nothing pointing at it.
    final previous = _entries[key];
    if (previous != null && previous.value.location != viewable.location) {
      final deleted = await _deleteContentOf(key, previous.value.location);
      if (deleted case Err()) {
        _entries.remove(key);
        return deleted;
      }
    }
    _entries[key] = CacheEntry(value: viewable, cachedAt: cachedAt);
    return ok<void>(null);
  });

  @override
  Future<Result<CacheEntry<ViewableDocument>?, StorageReadFailedError>> read(
    UserId owner,
    DocumentId id,
  ) => _inOrder(() async {
    final entry = _entries[_entryKey(owner, id)];
    if (entry == null) {
      return ok<CacheEntry<ViewableDocument>?>(null);
    }
    switch (await contentExists(_files, entry.value.location)) {
      case Err(:final error):
        return err(storageReadFailed(error.cause));
      case Ok(value: true):
        return ok<CacheEntry<ViewableDocument>?>(entry);
      case Ok():
        return ok<CacheEntry<ViewableDocument>?>(null);
    }
  });

  @override
  Future<Result<void, StorageWriteFailedError>> remove(
    UserId owner,
    DocumentId id,
  ) => _inOrder(() async {
    final key = _entryKey(owner, id);
    final entry = _entries[key];
    if (entry == null) {
      return ok<void>(null);
    }
    final deleted = await _deleteContentOf(key, entry.value.location);
    if (deleted case Err()) {
      return deleted;
    }
    _entries.remove(key);
    return ok<void>(null);
  });

  @override
  Future<Result<void, StorageWriteFailedError>> purge() => _inOrder(() async {
    for (final entry in List.of(_entries.entries)) {
      final key = entry.key;
      final deleted = await _deleteContentOf(key, entry.value.value.location);
      if (deleted case Err()) {
        return deleted;
      }
      _entries.remove(key);
    }
    // What no entry points at goes too: purging leaves nothing of any document
    // on the device.
    switch (await _files.deleteAll()) {
      case Ok():
        return ok<void>(null);
      case Err(:final error):
        return err(storageWriteFailed(error.cause));
    }
  });

  // Drops an entry and, best effort, its content.
  Future<void> _drop(String key) async {
    final entry = _entries.remove(key);
    if (entry == null) {
      return;
    }
    await _deleteContentOf(key, entry.value.location);
  }

  // Deletes the file of an entry, unless another entry still points at it.
  Future<Result<void, StorageWriteFailedError>> _deleteContentOf(
    String key,
    DocumentLocation location,
  ) async {
    final shared = _entries.entries.any(
      (other) => other.key != key && other.value.value.location == location,
    );
    if (shared) {
      return ok<void>(null);
    }
    switch (await deleteContent(_files, location)) {
      case Ok():
        return ok<void>(null);
      case Err(:final error):
        return err(storageWriteFailed(error.cause));
    }
  }
}

// JSON keeps the parts apart whatever characters the ids contain.
String _entryKey(UserId owner, DocumentId id) => jsonEncode([owner, id]);
