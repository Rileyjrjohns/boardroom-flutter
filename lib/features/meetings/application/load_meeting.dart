import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/application/offline/load_with_cache_fallback.dart';
import 'package:boardroom/core/application/offline/loaded.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/types/cache_entry.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/auth/application/session/require_session.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_document_evictor.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_repository.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';

/// What [loadMeeting] needs, on top of what the cache fallback needs.
abstract interface class LoadMeetingDeps
    implements CacheFallbackDeps, RequireSessionDeps {
  /// The remote meetings.
  MeetingRepository get meetings;

  /// The local cache of meetings.
  MeetingCache get meetingCache;

  /// Where the documents of a refused meeting are dropped from the device.
  MeetingDocumentEvictor get documentEvictor;
}

/// A meeting for [owner], from the remote source or, when it cannot be reached,
/// from the cache of that owner (see [loadWithCacheFallback]). When the server
/// refuses the meeting (`forbidden`, `notFound`), the cached copy goes, and so
/// do the documents it lists (through the [MeetingDocumentEvictor]): a document
/// of a meeting that the user can no longer see must not stay readable
/// offline.
///
/// The failure is a [RepositoryError], a `SessionRequiredError` or a
/// `SessionChangedError`.
Future<Result<Loaded<Meeting>, AppError>> loadMeeting(
  LoadMeetingDeps deps,
  UserId owner,
  MeetingId id,
) => loadWithCacheFallback<Meeting, RepositoryError>(
  deps,
  owner,
  CacheFallbackSource(
    resource: CacheResource.meeting,
    attributes: {LogAttribute.meetingId: id},
    fetch: () => deps.meetings.get(id),
    save: (meeting, cachedAt) =>
        deps.meetingCache.saveMeeting(owner, meeting, cachedAt),
    read: () => deps.meetingCache.readMeeting(owner, id),
    remove: () => deps.meetingCache.removeMeeting(owner, id),
    revoke: () => _revokeMeeting(deps, owner, id),
  ),
);

/// Removes the cached meeting and every document it lists. The documents are
/// read from the cached copy, so they go first: the copy is what says which
/// ones they are. A meeting that was never cached lists nothing.
Future<Result<void, StorageError>> _revokeMeeting(
  LoadMeetingDeps deps,
  UserId owner,
  MeetingId id,
) async {
  final List<Document> documents;
  switch (await deps.meetingCache.readMeeting(owner, id)) {
    case Err(:final error):
      return err(error);
    case Ok(:final CacheEntry<Meeting>? value):
      documents = value?.value.documents ?? const [];
  }

  for (final document in documents) {
    final removed = await deps.documentEvictor.evict(owner, document.id);
    if (removed case Err(:final error)) {
      return err(error);
    }
  }
  final removed = await deps.meetingCache.removeMeeting(owner, id);
  if (removed case Err(:final error)) {
    return err(error);
  }
  return ok<void>(null);
}
