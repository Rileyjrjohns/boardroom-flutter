import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';

/// What [purgeCaches] needs.
abstract interface class PurgeCachesDeps {
  /// The cache of meetings.
  MeetingCache get meetingCache;

  /// The cache of documents.
  DocumentCache get documentCache;

  /// Where a failed purge is reported.
  Monitoring get monitoring;
}

/// Empties the meeting cache and the document cache (the content of the
/// documents included), for every owner. Called when a session ends, so that
/// nothing a user saw stays on the device. Both are always attempted. A failure
/// is captured and never returned: it must not stop a user from signing out.
Future<void> purgeCaches(PurgeCachesDeps deps) async {
  final PurgeCachesDeps(:meetingCache, :documentCache, :monitoring) = deps;

  final meetings = await meetingCache.purge();
  if (meetings case Err(:final error)) {
    monitoring.captureError(MonitoringEvent.cachePurgeFailed, error, {
      LogAttribute.resource: CacheResource.meeting.value,
    });
  }

  final documents = await documentCache.purge();
  if (documents case Err(:final error)) {
    monitoring.captureError(MonitoringEvent.cachePurgeFailed, error, {
      LogAttribute.resource: CacheResource.document.value,
    });
  }
}
