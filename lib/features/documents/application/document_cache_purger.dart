import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/session_data_purger.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';

/// What the documents leave on the device for a session (the entries and the
/// content of the documents viewed), emptied when the session ends.
final class DocumentCachePurger implements SessionDataPurger {
  /// Creates the purger of [_cache].
  const new(this._cache);

  final DocumentCache _cache;

  @override
  CacheResource get resource => CacheResource.document;

  @override
  Future<Result<void, StorageWriteFailedError>> purge() => _cache.purge();
}
