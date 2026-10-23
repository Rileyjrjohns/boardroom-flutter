import 'package:boardroom/app/composition/meeting_cache_vote_recorder.dart';
import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/types/cache_entry.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/auth/application/session/end_session.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:test/test.dart';

import '../../support/builders/builders.dart';
import '../../support/fakes/create_fakes.dart';
import '../../support/fakes/fake_monitoring.dart';
import '../../support/fakes/holding_meeting_cache.dart';

// The scenarios of `recordVoteInCache` in React Native. In Dart the function is
// the `MeetingCacheVoteRecorder` of the composition, the implementation of the
// `RecordedVoteSink` port of the votes (see docs/architecture.md), so the
// scenarios, with the same names, run against it. The file keeps the name of
// the React Native test file, which `tool/scenario_parity.dart` maps by name.

/// Records [vote] with the recorder of the app, over the cache of meetings of
/// [fakes] or over [cache], the Dart counterpart of
/// `{ ...fakes, meetingCache: cache }`.
Future<void> _record(Fakes fakes, Vote vote, {MeetingCache? cache}) =>
    MeetingCacheVoteRecorder(
      meetingCache: cache ?? fakes.meetingCache,
      session: fakes,
    ).record(vote);

final Vote _vote = aVote(choice: VoteChoice.abstain);
final Instant _cachedAt = at(-5000);
final _attributes = <LogAttribute, Object>{
  LogAttribute.meetingId: aMeetingId(),
  LogAttribute.resource: CacheResource.meeting.value,
};

void main() {
  group('recordVoteInCache', () {
    test('records the vote on the cached meeting of the voter and keeps the '
        'date it was cached at', () async {
      final fakes = createFakes();
      await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), _cachedAt);
      fakes.clock.advance(60000);

      await _record(fakes, _vote);

      final cached = unwrap(
        await fakes.meetingCache.readMeeting(aUserId(), aMeetingId()),
      );
      expect(cached?.cachedAt, equals(_cachedAt));
      expect(
        cached == null
            ? null
            : findResolution(cached.value, aResolutionId())?.recordedVote,
        equals(VoteChoice.abstain),
      );
    });

    test('does not touch the cached meeting of another user', () async {
      final fakes = createFakes();
      await fakes.meetingCache.saveMeeting(
        aUserId('user-2'),
        aMeeting(),
        _cachedAt,
      );

      await _record(fakes, _vote);

      final cached = await fakes.meetingCache.readMeeting(
        aUserId('user-2'),
        aMeetingId(),
      );
      expect(
        cached,
        equals(ok(CacheEntry(value: aMeeting(), cachedAt: _cachedAt))),
      );
    });

    test('does nothing when the meeting is not cached', () async {
      final fakes = createFakes();

      await _record(fakes, _vote);

      expect(fakes.meetingCache.isEmpty(), isTrue);
      expect(fakes.monitoring.errors, isEmpty);
    });

    test('captures a cache that cannot be read, and does not fail', () async {
      final fakes = createFakes();
      fakes.meetingCache.readFailure = storageReadFailed();

      await _record(fakes, _vote);

      expect(
        fakes.monitoring.errors,
        equals([
          ErrorRecord(
            event: MonitoringEvent.cacheReadFailed,
            error: storageReadFailed(),
            attributes: _attributes,
          ),
        ]),
      );
    });

    test(
      'captures a cache that cannot be written, and does not fail',
      () async {
        final fakes = createFakes();
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), _cachedAt);
        fakes.meetingCache.writeFailure = storageWriteFailed();

        await _record(fakes, _vote);

        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.cacheWriteFailed,
              error: storageWriteFailed(),
              attributes: _attributes,
            ),
          ]),
        );
      },
    );

    group('when the user changes while the meeting is being read', () {
      test('writes nothing back after the user signed out and the caches were '
          'emptied', () async {
        final fakes = createFakes();
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), _cachedAt);
        final cache = HoldingMeetingCache(fakes.meetingCache);
        final held = cache.holdNextRead();

        final recording = _record(fakes, _vote, cache: cache);
        await held.hasAnswered;
        await closeSession(fakes);
        expect(fakes.meetingCache.isEmpty(), isTrue);
        held.release();
        await recording;

        expect(fakes.meetingCache.isEmpty(), isTrue);
      });

      test('writes nothing back after somebody else signed in', () async {
        final fakes = createFakes();
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), _cachedAt);
        final cache = HoldingMeetingCache(fakes.meetingCache);
        final held = cache.holdNextRead();

        final recording = _record(fakes, _vote, cache: cache);
        await held.hasAnswered;
        fakes.auth.session = aSession(user: aUser(id: aUserId('user-2')));
        await fakes.meetingCache.purge();
        held.release();
        await recording;

        expect(fakes.meetingCache.isEmpty(), isTrue);
      });

      test('writes nothing back while the app is locked', () async {
        final fakes = createFakes();
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), _cachedAt);
        final cache = HoldingMeetingCache(fakes.meetingCache);
        final held = cache.holdNextRead();

        final recording = _record(fakes, _vote, cache: cache);
        await held.hasAnswered;
        fakes.appLock.lock();
        await fakes.meetingCache.purge();
        held.release();
        await recording;

        expect(fakes.meetingCache.isEmpty(), isTrue);
      });

      test('still writes the vote when the same user is still signed in after '
          'the read', () async {
        final fakes = createFakes();
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), _cachedAt);
        final cache = HoldingMeetingCache(fakes.meetingCache);
        final held = cache.holdNextRead();

        final recording = _record(fakes, _vote, cache: cache);
        await held.hasAnswered;
        held.release();
        await recording;

        final cached = unwrap(
          await fakes.meetingCache.readMeeting(aUserId(), aMeetingId()),
        );
        expect(
          cached == null
              ? null
              : findResolution(cached.value, aResolutionId())?.recordedVote,
          equals(VoteChoice.abstain),
        );
      });
    });
  });
}
