import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/application/offline/loaded.dart';
import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/application/use_cases/restore_session.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/votes/application/ports/vote_outbox.dart';
import 'package:boardroom/features/votes/application/use_cases/cast_vote.dart';
import 'package:boardroom/features/votes/application/use_cases/sync_pending_votes.dart';
import 'package:test/test.dart';

// The values that are logged, stored or mapped to a prompt, pinned as strings:
// a test that compares a constant with itself would not notice a change.

/// The members of an enumeration by name, with their stable strings: the
/// counterpart of the `as const` object of the React Native code, whose keys
/// are the members.
Map<String, String> _pinned(Iterable<StableValue> members) => {
  for (final member in members) (member as Enum).name: member.value,
};

void main() {
  group('the values of the application', () {
    test('are those of the results and statuses the presentation reads', () {
      expect(
        _pinned(Freshness.values),
        equals({'fresh': 'fresh', 'stale': 'stale'}),
      );
      expect(
        _pinned(CastVoteStatus.values),
        equals({'submitted': 'submitted', 'queued': 'queued'}),
      );
      expect(
        _pinned(SyncOutcome.values),
        equals({
          'completed': 'completed',
          'interrupted': 'interrupted',
          'alreadyRunning': 'alreadyRunning',
        }),
      );
      expect(
        _pinned(SessionRestore.values),
        equals({'none': 'none', 'unlockRequired': 'unlockRequired'}),
      );
      expect(
        _pinned(EnqueueOutcome.values),
        equals({
          'enqueued': 'enqueued',
          'alreadyQueued': 'alreadyQueued',
          'heldByUnreadable': 'heldByUnreadable',
        }),
      );
    });

    test('are those of the reasons and kinds that cross the ports', () {
      expect(
        _pinned(BiometricReason.values),
        equals({'unlockApp': 'unlockApp', 'confirmVote': 'confirmVote'}),
      );
      expect(
        _pinned(ConnectivityStatus.values),
        equals({'online': 'online', 'offline': 'offline'}),
      );
      expect(
        _pinned(ScreenCaptureKind.values),
        equals({
          'screenshotTaken': 'screenshotTaken',
          'recordingStarted': 'recordingStarted',
          'recordingStopped': 'recordingStopped',
        }),
      );
    });

    test('are those of the monitoring vocabulary', () {
      expect(
        _pinned(LogLevel.values),
        equals({'info': 'info', 'warn': 'warn'}),
      );
      expect(
        _pinned(CacheResource.values),
        equals({
          'meetingPage': 'meetingPage',
          'meeting': 'meeting',
          'document': 'document',
        }),
      );
      expect(
        _pinned(MonitoringEvent.values),
        equals({
          'sessionExpired': 'sessionExpired',
          'signOutFailed': 'signOutFailed',
          'cacheReadFailed': 'cacheReadFailed',
          'cacheWriteFailed': 'cacheWriteFailed',
          'cacheRemoveFailed': 'cacheRemoveFailed',
          'cachePurgeFailed': 'cachePurgeFailed',
          'cacheEntryDiscarded': 'cacheEntryDiscarded',
          'servedFromCache': 'servedFromCache',
          'documentContentNotStored': 'documentContentNotStored',
          'orphanFileNotDeleted': 'orphanFileNotDeleted',
          'documentOpened': 'documentOpened',
          'screenCaptureDetected': 'screenCaptureDetected',
          'voteSubmitted': 'voteSubmitted',
          'voteSubmitFailed': 'voteSubmitFailed',
          'voteQueued': 'voteQueued',
          'voteEnqueueFailed': 'voteEnqueueFailed',
          'voteRejected': 'voteRejected',
          'voteAttemptNotRecorded': 'voteAttemptNotRecorded',
          'voteSyncCompleted': 'voteSyncCompleted',
          'voteSyncInterrupted': 'voteSyncInterrupted',
          'outboxReadFailed': 'outboxReadFailed',
          'storedRowDiscarded': 'storedRowDiscarded',
          'storedRowQuarantined': 'storedRowQuarantined',
          'responseInvalid': 'responseInvalid',
          'databaseRecreated': 'databaseRecreated',
          'connectivityListenerFailed': 'connectivityListenerFailed',
          'screenProtectionListenerFailed': 'screenProtectionListenerFailed',
          'screenProtectionNativeFailed': 'screenProtectionNativeFailed',
          'biometricMisconfigured': 'biometricMisconfigured',
          'unreadableVotesDiscarded': 'unreadableVotesDiscarded',
          'monitoringNotStarted': 'monitoringNotStarted',
          'resetNoticeUnreadable': 'resetNoticeUnreadable',
          'resetNoticeNotCleared': 'resetNoticeNotCleared',
        }),
      );
      expect(
        _pinned(LogAttribute.values),
        equals({
          'userId': 'userId',
          'meetingId': 'meetingId',
          'resolutionId': 'resolutionId',
          'documentId': 'documentId',
          'period': 'period',
          'resource': 'resource',
          'freshness': 'freshness',
          'confidentiality': 'confidentiality',
          'captureKind': 'captureKind',
          'errorCode': 'errorCode',
          'attempts': 'attempts',
          'synced': 'synced',
          'rejected': 'rejected',
          'remaining': 'remaining',
          'discarded': 'discarded',
          'issuePaths': 'issuePaths',
          'reason': 'reason',
        }),
      );
    });
  });
}
