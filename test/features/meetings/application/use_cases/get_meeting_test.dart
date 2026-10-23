import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/application/offline/loaded.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/types/cache_entry.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/use_cases/sign_out.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:boardroom/features/meetings/application/use_cases/get_meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/fakes/create_fakes.dart';
import '../../../../support/fakes/fake_monitoring.dart';

final Meeting _meeting = aMeeting();
final LogAttributes _meetingAttributes = {
  LogAttribute.meetingId: aMeetingId(),
  LogAttribute.resource: CacheResource.meeting.value,
};

({Fakes fakes, GetMeeting useCase}) _setup() {
  final fakes = createFakes();
  fakes.meetings.addMeeting(_meeting);
  return (fakes: fakes, useCase: GetMeeting(fakes));
}

void _signInAsB(Fakes fakes) {
  fakes.auth.session = aSession(
    user: aUser(id: aUserId('user-B'), email: anEmail('b@example.com')),
  );
}

Future<Result<Loaded<Meeting>, GetMeetingError>> _get(GetMeeting useCase) =>
    useCase.execute(meetingId: aMeetingId());

Result<Loaded<Meeting>, GetMeetingError> _fresh() =>
    ok(Loaded(data: _meeting, source: const DataSource.fresh(), loadedAt: now));

void main() {
  group('GetMeeting', () {
    test('returns the meeting from the server, flagged fresh, and caches it '
        'for the signed-in user', () async {
      final (:fakes, :useCase) = _setup();

      final result = await _get(useCase);

      expect(result, equals(_fresh()));
      expect(
        await fakes.meetingCache.readMeeting(aUserId(), aMeetingId()),
        equals(ok(CacheEntry(value: _meeting, cachedAt: now))),
      );
    });

    group('the session', () {
      test('is required: without one nothing is read, not even from the '
          'cache', () async {
        final (:fakes, :useCase) = _setup();
        await _get(useCase);
        fakes.auth.session = null;
        fakes.network.goOffline();

        expect(await _get(useCase), equals(err(notAuthenticated())));
        expect(fakes.meetings.getCalls, hasLength(1));
      });

      test('must not have expired', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.session = aSession(expiresAt: now);

        expect(await _get(useCase), equals(err(sessionExpired())));
        expect(fakes.meetings.getCalls, isEmpty);
      });
    });

    group('the offline policy', () {
      test('logs that a cached meeting was served, with the id of the '
          'meeting', () async {
        final (:fakes, :useCase) = _setup();
        await _get(useCase);
        fakes.network.goOffline();

        await _get(useCase);

        expect(
          fakes.monitoring.logs,
          equals([
            LogRecord(
              level: LogLevel.info,
              event: MonitoringEvent.servedFromCache,
              attributes: _meetingAttributes,
            ),
          ]),
        );
      });

      test('serves the cached meeting flagged stale when there is no '
          'network', () async {
        final (:fakes, :useCase) = _setup();
        await _get(useCase);
        fakes.network.goOffline();
        fakes.clock.advance(1800000);

        final result = await _get(useCase);

        expect(
          result,
          equals(
            ok(
              Loaded(
                data: _meeting,
                source: DataSource.stale(cachedAt: now),
                loadedAt: at(1800000),
              ),
            ),
          ),
        );
      });

      test('returns the network error for a meeting that was never '
          'viewed', () async {
        final (:fakes, :useCase) = _setup();
        fakes.network.goOffline();

        expect(await _get(useCase), equals(err(networkUnavailable())));
      });

      test('returns the fresh meeting when the cache cannot be '
          'written', () async {
        final (:fakes, :useCase) = _setup();
        fakes.meetingCache.writeFailure = storageWriteFailed();

        final result = await _get(useCase);

        expect(result, equals(_fresh()));
        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.cacheWriteFailed,
              error: storageWriteFailed(),
              attributes: _meetingAttributes,
            ),
          ]),
        );
      });

      test('returns the network error when the cache cannot be read '
          'either', () async {
        final (:fakes, :useCase) = _setup();
        fakes.network.goOffline();
        fakes.meetingCache.readFailure = storageReadFailed();

        expect(await _get(useCase), equals(err(networkUnavailable())));
        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.cacheReadFailed,
              error: storageReadFailed(),
              attributes: _meetingAttributes,
            ),
          ]),
        );
      });

      test('refuses a cached meeting older than the maximum age, and one '
          'dated in the future', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.session = aSession(expiresAt: at(30 * millisPerDay));
        await _get(useCase);
        fakes.network.goOffline();

        fakes.clock.advance(7 * millisPerDay);
        expect(
          await _get(useCase),
          equals(
            ok(
              Loaded(
                data: _meeting,
                source: DataSource.stale(cachedAt: now),
                loadedAt: at(7 * millisPerDay),
              ),
            ),
          ),
        );
        fakes.clock.advance(1);
        expect(await _get(useCase), equals(err(networkUnavailable())));

        fakes.clock.set(at(-1));
        expect(await _get(useCase), equals(err(networkUnavailable())));
      });
    });

    group('a user who is not the one who cached the meeting', () {
      test('finds nothing of it, even offline: A views a meeting, B signs in '
          'without any sign-out in between', () async {
        final (:fakes, :useCase) = _setup();
        await _get(useCase);
        _signInAsB(fakes);
        fakes.network.goOffline();

        expect(await _get(useCase), equals(err(networkUnavailable())));
      });

      test('finds nothing of it after A signed out and B signed in: the '
          'sign-out emptied the cache', () async {
        final (:fakes, :useCase) = _setup();
        await _get(useCase);
        await SignOut(fakes).execute();
        _signInAsB(fakes);
        fakes.appLock.unlock();
        fakes.network.goOffline();

        expect(await _get(useCase), equals(err(networkUnavailable())));
        expect(fakes.meetingCache.isEmpty(), isTrue);
      });

      test('empties the copy of A too when B is refused by the server: the '
          'refusal of a session empties the caches of every owner', () async {
        final (:fakes, :useCase) = _setup();
        await _get(useCase);
        _signInAsB(fakes);
        fakes.meetings.failure = unauthorized();
        await _get(useCase);

        expect(
          await fakes.meetingCache.readMeeting(aUserId(), aMeetingId()),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );
      });
    });

    group('an authoritative refusal of the server', () {
      test('evicts the cached copy when the user is refused, and the copy is '
          'not served afterwards', () async {
        final (:fakes, :useCase) = _setup();
        await _get(useCase);
        fakes.meetings.failure = unauthorized();

        expect(await _get(useCase), equals(err(unauthorized())));
        expect(
          await fakes.meetingCache.readMeeting(aUserId(), aMeetingId()),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );

        fakes.meetings.failure = null;
        // The refused session is over: the user signs in again, and finds no
        // saved copy.
        fakes.auth.session = aSession();
        fakes.appLock.unlock();
        fakes.network.goOffline();
        expect(await _get(useCase), equals(err(networkUnavailable())));
      });

      test('evicts the cached copy when the meeting no longer '
          'exists', () async {
        final (:fakes, :useCase) = _setup();
        await _get(useCase);
        fakes.meetings.removeMeeting(aMeetingId());

        expect(await _get(useCase), equals(err(notFound())));
        expect(
          await fakes.meetingCache.readMeeting(aUserId(), aMeetingId()),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );
      });

      test('evicts the cached copy when the meeting is forbidden to the user, '
          'the documents it lists with it', () async {
        final (:fakes, :useCase) = _setup();
        await _get(useCase);
        await fakes.documentCache.save(
          aUserId(),
          ViewableDocument(
            document: _meeting.documents.firstOrNull ?? aDocument(),
            location: aDocumentLocation(),
          ),
          now,
        );
        fakes.meetings.forbid(aMeetingId());

        expect(await _get(useCase), equals(err(forbidden())));
        expect(
          await fakes.meetingCache.readMeeting(aUserId(), aMeetingId()),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );
        expect(fakes.documentCache.isEmpty(), isTrue);
      });

      test('empties both caches, and captures the failure, when the copy '
          'cannot be evicted', () async {
        final (:fakes, :useCase) = _setup();
        await _get(useCase);
        fakes.meetings.forbid(aMeetingId());
        fakes.meetingCache.removeFailure = storageWriteFailed();

        expect(await _get(useCase), equals(err(forbidden())));
        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.cacheRemoveFailed,
              error: storageWriteFailed(),
              attributes: _meetingAttributes,
            ),
          ]),
        );
        expect(fakes.meetingCache.isEmpty(), isTrue);
      });

      test('captures the failure of the purge when the session is refused and '
          'the caches cannot be emptied', () async {
        final (:fakes, :useCase) = _setup();
        await _get(useCase);
        fakes.meetings.failure = unauthorized();
        fakes.meetingCache.purgeFailure = storageWriteFailed();

        expect(await _get(useCase), equals(err(unauthorized())));
        expect(
          fakes.monitoring.capturedEvents(),
          equals([MonitoringEvent.cachePurgeFailed]),
        );
      });
    });
  });
}
