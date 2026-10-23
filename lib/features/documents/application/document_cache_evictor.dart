import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_document_evictor.dart';

/// Drops the copy of a document from the document cache: the way the documents
/// of a meeting that the server refuses leave the device (see
/// [MeetingDocumentEvictor]).
final class DocumentCacheEvictor implements MeetingDocumentEvictor {
  /// Creates the evictor over [_cache].
  const new(this._cache);

  final DocumentCache _cache;

  @override
  Future<Result<void, StorageWriteFailedError>> evict(
    UserId owner,
    DocumentId id,
  ) => _cache.remove(owner, id);
}
