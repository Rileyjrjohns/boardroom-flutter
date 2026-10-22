import 'package:boardroom/application/ports/meeting_cache.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/ports/types/cache_entry.dart';
import 'package:boardroom/application/shared/cache_resource.dart';
import 'package:boardroom/application/shared/loaded.dart';
import 'package:boardroom/application/use_cases/meetings/list_meetings.dart';
import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/meeting_period.dart';
import 'package:boardroom/domain/value_objects/page.dart';
import 'package:boardroom/domain/value_objects/page_cursor.dart';
import 'package:boardroom/domain/value_objects/page_request.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import '../../support/create_fakes.dart';
import '../../support/fake_monitoring.dart';

/// What the use case is asked: the period and the page.
typedef _Input = ({MeetingPeriod period, PageRequest request});
typedef _Listed = Result<Loaded<Page<MeetingSummary>>, ListMeetingsError>;
typedef _Succeeded = Ok<Loaded<Page<MeetingSummary>>, ListMeetingsError>;

const MeetingPeriod _upcoming = MeetingPeriod.upcoming;
const MeetingPeriod _past = MeetingPeriod.past;

// Upcoming: soonest first is 1, 2, 3. Past: latest first is 4, 5.
final MeetingSummary _m1 = aMeetingSummary(
  id: aMeetingId(), // 'meeting-1', the default
  scheduledAt: at(millisPerDay),
);
final MeetingSummary _m2 = aMeetingSummary(
  id: aMeetingId('meeting-2'),
  scheduledAt: at(2 * millisPerDay),
);
final MeetingSummary _m3 = aMeetingSummary(
  id: aMeetingId('meeting-3'),
  scheduledAt: at(3 * millisPerDay),
);
final MeetingSummary _m4 = aMeetingSummary(
  id: aMeetingId('meeting-4'),
  scheduledAt: at(-millisPerDay),
);
final MeetingSummary _m5 = aMeetingSummary(
  id: aMeetingId('meeting-5'),
  scheduledAt: at(-2 * millisPerDay),
);

final PageCursor _cursor = unwrap(parsePageCursor('meeting-2'));
final Page<MeetingSummary> _firstPage = createPage([_m1, _m2], _cursor);
final Page<MeetingSummary> _secondPage = createPage([_m3]);

/// The page of [limit] meetings after [cursor] (the first page when absent).
PageRequest _request(int limit, [PageCursor? cursor]) =>
    unwrap(createPageRequest(cursor: cursor, limit: limit));

final _Input _first = (period: _upcoming, request: _request(2));
final _Input _second = (period: _upcoming, request: _request(2, _cursor));
final _Input _pastPage = (period: _past, request: _request(2));
final _Input _wide = (period: _upcoming, request: _request(3));

({Fakes fakes, ListMeetings useCase}) _setup() {
  final fakes = createFakes();
  // Not in order: the server sorts them.
  fakes.meetings.setMeetings(_upcoming, [_m3, _m1, _m2]);
  fakes.meetings.setMeetings(_past, [_m5, _m4]);
  return (fakes: fakes, useCase: ListMeetings(fakes));
}

/// User B signs in on the device.
void _signInAsB(Fakes fakes) {
  fakes.auth.session = aSession(
    user: aUser(id: aUserId('user-B'), email: anEmail('b@example.com')),
  );
}

Future<_Listed> _list(ListMeetings useCase, _Input input) =>
    useCase.execute(period: input.period, request: input.request);

_Listed _fresh(Page<MeetingSummary> page) =>
    ok(Loaded(data: page, source: const DataSource.fresh(), loadedAt: now));

void main() {
  group('ListMeetings', () {
    group('what the server serves', () {
      test('returns the first page, flagged fresh, soonest meeting first for '
          'the upcoming ones', () async {
        final (:fakes, :useCase) = _setup();

        final result = await _list(useCase, _first);

        expect(result, equals(_fresh(_firstPage)));
        expect(fakes.meetings.listCalls, equals([_first]));
      });

      test('follows the cursor to the next page', () async {
        final (:fakes, :useCase) = _setup();

        final result = await _list(useCase, _second);

        expect(result, equals(_fresh(_secondPage)));
      });

      test('returns the past meetings latest first', () async {
        final (:fakes, :useCase) = _setup();

        final result = await _list(useCase, _pastPage);

        expect(
          result,
          isA<_Succeeded>().having(
            (r) => r.value.data.items,
            'items',
            equals([_m4, _m5]),
          ),
        );
      });

      test('asks for the page size it is given', () async {
        final (:fakes, :useCase) = _setup();

        final result = await _list(useCase, (
          period: _upcoming,
          request: _request(1),
        ));

        expect(
          result,
          isA<_Succeeded>().having(
            (r) => r.value.data,
            'data',
            equals(createPage([_m1], unwrap(parsePageCursor('meeting-1')))),
          ),
        );
      });
    });

    group('the session', () {
      test('is required: without one, nothing is read from the server nor from '
          'the cache', () async {
        final (:fakes, :useCase) = _setup();
        await _list(useCase, _first);
        fakes.auth.session = null;
        fakes.network.goOffline();

        expect(await _list(useCase, _first), equals(err(notAuthenticated())));
        expect(fakes.meetings.listCalls, hasLength(1));
      });

      test('must not have expired', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.session = aSession(expiresAt: now);

        expect(await _list(useCase, _first), equals(err(sessionExpired())));
        expect(fakes.meetings.listCalls, isEmpty);
      });
    });

    group('the cache', () {
      test('is written through with every fresh page, for the signed-in user, '
          'stamped by the clock', () async {
        final (:fakes, :useCase) = _setup();
        fakes.clock.advance(1000);
        await _list(useCase, _first);

        final cached = await fakes.meetingCache.readPage(
          aUserId(),
          const MeetingPageKey(period: _upcoming, limit: 2),
        );

        expect(
          cached,
          equals(ok(CacheEntry(value: _firstPage, cachedAt: at(1000)))),
        );
      });

      test('serves the cached page flagged stale, with its age, when there is '
          'no network', () async {
        final (:fakes, :useCase) = _setup();
        await _list(useCase, _first);
        fakes.network.goOffline();
        fakes.clock.advance(1800000);

        final result = await _list(useCase, _first);

        expect(
          result,
          equals(
            ok(
              Loaded(
                data: _firstPage,
                source: DataSource.stale(cachedAt: now),
                loadedAt: at(1800000),
              ),
            ),
          ),
        );
      });

      test('gives back the right page offline after several were fetched: one '
          'entry per period, cursor and page size', () async {
        final (:fakes, :useCase) = _setup();
        for (final input in [_first, _second, _pastPage, _wide]) {
          await _list(useCase, input);
        }
        fakes.network.goOffline();

        Future<Object> offline(_Input input) async {
          switch (await _list(useCase, input)) {
            case Ok(:final value):
              return [value.source.freshness, value.data.items];
            case Err(:final error):
              return error;
          }
        }

        expect(
          await offline(_first),
          equals([
            Freshness.stale,
            [_m1, _m2],
          ]),
        );
        expect(
          await offline(_second),
          equals([
            Freshness.stale,
            [_m3],
          ]),
        );
        expect(
          await offline(_pastPage),
          equals([
            Freshness.stale,
            [_m4, _m5],
          ]),
        );
        expect(
          await offline(_wide),
          equals([
            Freshness.stale,
            [_m1, _m2, _m3],
          ]),
        );
        expect(
          await offline((period: _upcoming, request: _request(10))),
          equals(networkUnavailable()),
        );
      });

      test('returns the network error when the page was never '
          'cached', () async {
        final (:fakes, :useCase) = _setup();
        fakes.network.goOffline();

        expect(await _list(useCase, _first), equals(err(networkUnavailable())));
      });

      test('keeps the pages of each user apart: B finds nothing of what A saw, '
          'and does not overwrite it', () async {
        final (:fakes, :useCase) = _setup();
        await _list(useCase, _first);
        _signInAsB(fakes);
        fakes.network.goOffline();
        expect(await _list(useCase, _first), equals(err(networkUnavailable())));

        fakes.network.goOnline();
        fakes.clock.advance(60000);
        await _list(useCase, _first);
        fakes.network.goOffline();
        final asB = await _list(useCase, _first);
        fakes.auth.session = aSession();
        final asA = await _list(useCase, _first);

        expect(
          asB,
          isA<_Succeeded>().having(
            (r) => r.value.source,
            'source',
            equals(DataSource.stale(cachedAt: at(60000))),
          ),
        );
        expect(
          asA,
          isA<_Succeeded>().having(
            (r) => r.value.source,
            'source',
            equals(DataSource.stale(cachedAt: now)),
          ),
        );
      });

      test('refuses a page that is older than the maximum age', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.session = aSession(expiresAt: at(30 * millisPerDay));
        await _list(useCase, _first);
        fakes.network.goOffline();

        fakes.clock.advance(7 * millisPerDay);
        final atTheLimit = await _list(useCase, _first);
        expect(
          atTheLimit,
          isA<_Succeeded>().having(
            (r) => r.value.source,
            'source',
            equals(DataSource.stale(cachedAt: now)),
          ),
        );

        fakes.clock.advance(1);
        expect(await _list(useCase, _first), equals(err(networkUnavailable())));
        expect(
          fakes.monitoring.logs.last,
          equals(
            LogRecord(
              level: LogLevel.warn,
              event: MonitoringEvent.cacheEntryDiscarded,
              attributes: {
                LogAttribute.period: _upcoming.value,
                LogAttribute.resource: CacheResource.meetingPage.value,
              },
            ),
          ),
        );
      });

      test('evicts the cached page when the server refuses, and does not '
          'serve it afterwards', () async {
        final (:fakes, :useCase) = _setup();
        await _list(useCase, _first);
        fakes.meetings.failure = unauthorized();

        expect(await _list(useCase, _first), equals(err(unauthorized())));
        expect(
          await fakes.meetingCache.readPage(
            aUserId(),
            const MeetingPageKey(period: _upcoming, limit: 2),
          ),
          equals(ok<CacheEntry<Page<MeetingSummary>>?>(null)),
        );

        fakes.meetings.failure = null;
        // The refused session is over: the user signs in again, and finds no
        // saved copy.
        fakes.auth.session = aSession();
        fakes.appLock.unlock();
        fakes.network.goOffline();
        expect(await _list(useCase, _first), equals(err(networkUnavailable())));
      });

      test('empties every cached page when the session is refused, not only '
          'the one that was asked for', () async {
        final (:fakes, :useCase) = _setup();
        await _list(useCase, _first);
        await _list(useCase, _second);
        fakes.meetings.failure = unauthorized();
        await _list(useCase, _first);

        expect(
          await fakes.meetingCache.readPage(
            aUserId(),
            MeetingPageKey(period: _upcoming, cursor: _cursor, limit: 2),
          ),
          equals(ok<CacheEntry<Page<MeetingSummary>>?>(null)),
        );
        expect(fakes.meetingCache.isEmpty(), isTrue);
      });

      test('leaves the cached page alone when the server fails '
          'unexpectedly', () async {
        final (:fakes, :useCase) = _setup();
        await _list(useCase, _first);
        fakes.meetings.failure = unexpected('HTTP 503');

        expect(
          await _list(useCase, _first),
          equals(err(unexpected('HTTP 503'))),
        );
        expect(
          await fakes.meetingCache.readPage(
            aUserId(),
            const MeetingPageKey(period: _upcoming, limit: 2),
          ),
          equals(ok(CacheEntry(value: _firstPage, cachedAt: now))),
        );
      });
    });

    group('the monitoring', () {
      final pageAttributes = <LogAttribute, Object>{
        LogAttribute.period: _upcoming.value,
        LogAttribute.resource: CacheResource.meetingPage.value,
      };

      test('captures a cache that cannot be written, with the period and the '
          'resource', () async {
        final (:fakes, :useCase) = _setup();
        fakes.meetingCache.writeFailure = storageWriteFailed();

        final result = await _list(useCase, _first);

        expect(result, equals(_fresh(_firstPage)));
        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.cacheWriteFailed,
              error: storageWriteFailed(),
              attributes: pageAttributes,
            ),
          ]),
        );
      });

      test('logs that a cached page was served, with the period and the '
          'resource', () async {
        final (:fakes, :useCase) = _setup();
        await _list(useCase, _first);
        fakes.network.goOffline();

        await _list(useCase, _first);

        expect(
          fakes.monitoring.logs,
          equals([
            LogRecord(
              level: LogLevel.info,
              event: MonitoringEvent.servedFromCache,
              attributes: pageAttributes,
            ),
          ]),
        );
      });

      test('captures a write-through that failed and a removal that failed, '
          'with the period and the resource', () async {
        final (:fakes, :useCase) = _setup();
        fakes.meetingCache.writeFailure = storageWriteFailed();
        fakes.meetingCache.removeFailure = storageWriteFailed();

        await _list(useCase, _first);

        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.cacheWriteFailed,
              error: storageWriteFailed(),
              attributes: pageAttributes,
            ),
            ErrorRecord(
              event: MonitoringEvent.cacheRemoveFailed,
              error: storageWriteFailed(),
              attributes: pageAttributes,
            ),
          ]),
        );
      });

      test('captures a purge that failed when the session is '
          'refused', () async {
        final (:fakes, :useCase) = _setup();
        fakes.meetings.failure = unauthorized();
        fakes.meetingCache.purgeFailure = storageWriteFailed();

        await _list(useCase, _first);

        expect(
          fakes.monitoring.capturedEvents(),
          equals([MonitoringEvent.cachePurgeFailed]),
        );
      });
    });
  });
}
