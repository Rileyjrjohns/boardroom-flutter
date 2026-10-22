import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/ports/types/cache_entry.dart';
import 'package:boardroom/application/shared/cache_resource.dart';
import 'package:boardroom/application/shared/require_session.dart';
import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/shared/result.dart';

/// Once the server has recorded a vote, records it on the cached copy of its
/// meeting too (`withVoteRecorded`), so that the copy shows the vote and the
/// voter cannot vote again from it while offline. The copy keeps the date it
/// was cached at: updating it does not make it younger.
///
/// A meeting that is not cached is fine, there is nothing to update. A cache
/// that cannot be read or written is captured and does not fail anything: the
/// server has recorded the vote and refuses a second one anyway.
///
/// The read and the write are two awaits, and a sign-out (which empties the
/// caches) can happen between them. The voter is checked again in between
/// ([requireSameUser]), and nothing is written unless the same user is still
/// signed in and the app is not locked: writing the copy back would put the
/// meeting of a user who left on the device again, after the purge that removed
/// it.
Future<void> recordVoteInCache(RequireSessionDeps deps, Vote vote) async {
  final RequireSessionDeps(:meetingCache, :monitoring) = deps;
  final attributes = <LogAttribute, Object>{
    LogAttribute.meetingId: vote.meetingId,
    LogAttribute.resource: CacheResource.meeting.value,
  };

  final CacheEntry<Meeting> cached;
  switch (await meetingCache.readMeeting(vote.voterId, vote.meetingId)) {
    case Err(:final error):
      monitoring.captureError(
        MonitoringEvent.cacheReadFailed,
        error,
        attributes,
      );
      return;
    case Ok(:final value):
      if (value == null) {
        return;
      }
      cached = value;
  }

  final stillTheVoter = await requireSameUser(deps, vote.voterId);
  if (stillTheVoter is Err) {
    return;
  }

  final saved = await meetingCache.saveMeeting(
    vote.voterId,
    withVoteRecorded(cached.value, vote),
    cached.cachedAt,
  );
  if (saved case Err(:final error)) {
    monitoring.captureError(
      MonitoringEvent.cacheWriteFailed,
      error,
      attributes,
    );
  }
}
