import 'dart:convert';

import 'package:boardroom/core/application/ports/types/cache_entry.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';

import 'copy_plain.dart';

/// An in-memory cache that keeps the entries of each owner apart, like the
/// contract says. A miss is `ok(null)`. It keeps copies of what it is given and
/// hands back copies of what it holds. It keeps no files: it cannot lose a
/// content, nor delete one.
class FakeDocumentCache implements DocumentCache {
  /// Makes the reads fail while set.
  StorageReadFailedError? readFailure;

  /// Makes `save` fail while set. Nothing new is stored, and the older entry
  /// for the same owner and document is dropped, as the port requires: it must
  /// not stay readable as if it were current.
  StorageWriteFailedError? writeFailure;

  /// Makes `remove` fail while set (the entry stays).
  StorageWriteFailedError? removeFailure;

  /// Makes `purge` fail while set (the entries stay).
  StorageWriteFailedError? purgeFailure;

  /// How many times `purge` was called.
  int purgeCalls = 0;

  final Map<String, CacheEntry<ViewableDocument>> _entries = {};

  /// True when nothing is stored for anybody.
  bool isEmpty() => _entries.isEmpty;

  @override
  Future<Result<void, StorageWriteFailedError>> save(
    UserId owner,
    ViewableDocument viewable,
    Instant cachedAt,
  ) async {
    final failure = writeFailure;
    if (failure != null) {
      _entries.remove(_entryKey(owner, viewable.document.id));
      return err(failure);
    }
    _entries[_entryKey(owner, viewable.document.id)] = copyPlain(
      CacheEntry(value: viewable, cachedAt: cachedAt),
    );
    return ok<void>(null);
  }

  @override
  Future<Result<CacheEntry<ViewableDocument>?, StorageReadFailedError>> read(
    UserId owner,
    DocumentId id,
  ) async {
    final failure = readFailure;
    if (failure != null) {
      return err(failure);
    }
    return ok(copyPlain(_entries[_entryKey(owner, id)]));
  }

  @override
  Future<Result<void, StorageWriteFailedError>> remove(
    UserId owner,
    DocumentId id,
  ) async {
    final failure = removeFailure;
    if (failure != null) {
      return err(failure);
    }
    _entries.remove(_entryKey(owner, id));
    return ok<void>(null);
  }

  @override
  Future<Result<void, StorageWriteFailedError>> purge() async {
    purgeCalls += 1;
    final failure = purgeFailure;
    if (failure != null) {
      return err(failure);
    }
    _entries.clear();
    return ok<void>(null);
  }
}

// JSON keeps the parts apart whatever characters the ids contain.
String _entryKey(UserId owner, DocumentId id) => jsonEncode([owner, id]);
