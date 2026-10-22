import 'package:boardroom/application/ports/auth_session.dart';
import 'package:boardroom/application/ports/clock.dart';
import 'package:boardroom/application/ports/document_cache.dart';
import 'package:boardroom/application/ports/meeting_cache.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/ports/types/cache_entry.dart';
import 'package:boardroom/application/shared/app_lock.dart';
import 'package:boardroom/application/shared/cache_resource.dart';
import 'package:boardroom/application/shared/end_session.dart';
import 'package:boardroom/application/shared/record_vote_in_cache.dart';
import 'package:boardroom/application/shared/require_session.dart';
import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/domain/value_objects/vote_choice.dart';
import 'package:test/test.dart';

import '../../domain/support/builders.dart';
import '../support/create_fakes.dart';
import '../support/fake_monitoring.dart';
import '../support/holding_meeting_cache.dart';

/// The fakes, with another cache of meetings: the Dart counterpart of
/// `{ ...fakes, meetingCache: cache }`, for a cache that is not a
/// `FakeMeetingCache`.
final class _DepsWithCache implements RequireSessionDeps {
  const new(this._fakes, this.meetingCache);

  final Fakes _fakes;

  @override
  final MeetingCache meetingCache;

  @override
  AuthSession get auth => _fakes.auth;

  @override
  Clock get clock => _fakes.clock;

  @override
  AppLock get appLock => _fakes.appLock;

  @override
  DocumentCache get documentCache => _fakes.documentCache;

  @override
  Monitoring get monitoring => _fakes.monitoring;
}

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

      await recordVoteInCache(fakes, _vote);

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

      await recordVoteInCache(fakes, _vote);

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

      await recordVoteInCache(fakes, _vote);

      expect(fakes.meetingCache.isEmpty(), isTrue);
      expect(fakes.monitoring.errors, isEmpty);
    });

    test('captures a cache that cannot be read, and does not fail', () async {
      final fakes = createFakes();
      fakes.meetingCache.readFailure = storageReadFailed();

      await recordVoteInCache(fakes, _vote);

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

        await recordVoteInCache(fakes, _vote);

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

        final recording = recordVoteInCache(
          _DepsWithCache(fakes, cache),
          _vote,
        );
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

        final recording = recordVoteInCache(
          _DepsWithCache(fakes, cache),
          _vote,
        );
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

        final recording = recordVoteInCache(
          _DepsWithCache(fakes, cache),
          _vote,
        );
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

        final recording = recordVoteInCache(
          _DepsWithCache(fakes, cache),
          _vote,
        );
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
