import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/types/cache_entry.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/session/require_session.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/votes/application/ports/recorded_vote_sink.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:boardroom/features/votes/domain/with_vote_recorded.dart';

/// Records a vote the server accepted on the cached copy of its meeting
/// (`withVoteRecorded`), so that the copy shows the vote and the voter cannot
/// vote again from it while offline. The copy keeps the date it was cached at:
/// updating it does not make it younger.
///
/// It is the implementation of the [RecordedVoteSink] port of the votes, over
/// the [MeetingCache] of the meetings and the session guard of `auth`. It is
/// glue between three features, so it lives in the composition and not in one
/// of them.
///
/// A meeting that is not cached is fine, there is nothing to update. A cache
/// that cannot be read or written is captured and does not fail anything: the
/// server has recorded the vote and refuses a second one anyway.
///
/// The read and the write are two awaits, and a sign-out (which empties the
/// caches) can happen between them. The voter is checked again in between
/// (`requireSameUser`), and nothing is written unless the same user is still
/// signed in and the app is not locked: writing the copy back would put the
/// meeting of a user who left on the device again, after the purge that removed
/// it.
final class MeetingCacheVoteRecorder implements RecordedVoteSink {
  /// Creates the recorder over [meetingCache]. [session] is what the session
  /// guard needs, and where a failure is reported.
  const new({required this.meetingCache, required this.session});

  /// The local cache of meetings.
  final MeetingCache meetingCache;

  /// What the session guard needs (the stored session, the clock, the lock),
  /// and the monitoring.
  final RequireSessionDeps session;

  @override
  Future<void> record(Vote vote) async {
    final monitoring = session.monitoring;
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

    final stillTheVoter = await requireSameUser(session, vote.voterId);
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
}
