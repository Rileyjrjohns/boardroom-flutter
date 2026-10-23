import 'dart:convert';

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/types/cache_entry.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/page.dart';
import 'package:boardroom/core/domain/value_objects/page_cursor.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/infrastructure/drift_meeting_cache.dart';
import 'package:boardroom/features/meetings/infrastructure/persistence/schema.dart';
import 'package:boardroom/features/meetings/infrastructure/stored_meeting.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/contracts/meeting_cache_contract.dart';
import '../../../support/contracts/support.dart';
import '../../../support/fakes/fake_monitoring.dart';
import '../../../support/infrastructure/encrypted_test_database.dart';
import '../../../support/infrastructure/test_database.dart';

/// The cache over a real SQLite database, and what the contract suite needs to
/// wreck it.
MeetingCacheHarness _harnessOf(TestDatabase test, FakeMonitoring monitoring) {
  final cache = DriftMeetingCache(
    database: test.database,
    monitoring: monitoring,
  );
  return MeetingCacheHarness(
    cache: cache,
    // A full disk: nothing can be added, but space can still be freed.
    breakWrites: () => test.faults.failWhileAddingData(true),
    repairWrites: () => test.faults.failWhileAddingData(false),
    failNextStatement: test.faults.failNext,
    reopen: test.file == null
        ? null
        : () async {
            final reopened = await test.reopen();
            return _harnessOf(reopened, monitoring).cache;
          },
  );
}

// What the contract cannot say: the rows are JSON that is checked when it is
// read back, and a row that does not pass is a miss, reported, and deleted.

final UserId _owner = aUserId('owner-1');
final Meeting _meeting = aMeeting();
const MeetingPageKey _pageKey = MeetingPageKey(
  period: MeetingPeriod.upcoming,
  limit: 10,
);

/// The stored form of the meeting, as a JSON object that can be changed.
Map<String, Object?> _storedMeeting() =>
    jsonDecode(jsonEncode(storedMeetingOf(_meeting).toJson()))
        as Map<String, Object?>;

/// Rows exactly as the first version of the cache wrote them, when it kept what
/// the API sends: the format of the database is a promise to the rows already
/// on the devices, which these hold it to.
final String _meetingWrittenBefore = [
  '{"id":"meeting-1","title":"Board of directors",',
  '"scheduledAt":"2030-03-18T17:46:40.000Z","location":"Room 1",',
  '"agenda":[{"id":"agenda-1","position":1,"title":"Budget",',
  '"resolution":{"id":"resolution-1","title":"Approve the budget",',
  '"description":"Approve the budget of the next financial year.",',
  '"status":"open"}}],',
  '"documents":[{"id":"document-1","title":"Financial statements",',
  '"confidentiality":"confidential","pageCount":3}],',
  '"participants":[{"userId":"user-1","fullName":"Alice Martin",',
  '"role":"member"},{"userId":"user-2","fullName":"Bruno Durand",',
  '"role":"chair"},{"userId":"user-3","fullName":"Chloe Petit",',
  '"role":"secretary"},{"userId":"user-4","fullName":"David Roux",',
  '"role":"guest"}]}',
].join();
final String _pageWrittenBefore = [
  '{"items":[{"id":"meeting-1","title":"Board of directors",',
  '"scheduledAt":"2030-03-18T17:46:40.000Z","location":"Room 1"}]}',
].join();

String get _details => MeetingStoredTable.meetingDetails.value;
String get _pages => MeetingStoredTable.meetingPages.value;

void main() {
  final directory = databaseDirectory();

  describeMeetingCacheContract(
    'DriftMeetingCache',
    () async => _harnessOf(await openTestDatabase(directory), FakeMonitoring()),
    const StoreContractOptions(failsStatements: true, survivesReopen: true),
  );

  // The same suite on a database in memory, which has no file to open again.
  describeMeetingCacheContract(
    'DriftMeetingCache in memory',
    () async => _harnessOf(await openTestDatabase(), FakeMonitoring()),
    const StoreContractOptions(failsStatements: true, survivesReopen: false),
  );

  // The same suite on the database the app opens: encrypted, with the key of
  // the secure storage.
  describeMeetingCacheContract(
    'DriftMeetingCache encrypted',
    () async => _harnessOf(
      await openEncryptedTestDatabase(directory),
      FakeMonitoring(),
    ),
    const StoreContractOptions(failsStatements: true, survivesReopen: true),
  );

  Future<
    ({TestDatabase test, FakeMonitoring monitoring, DriftMeetingCache cache})
  >
  openCache() async {
    final test = await openTestDatabase();
    final monitoring = FakeMonitoring();
    final cache = DriftMeetingCache(
      database: test.database,
      monitoring: monitoring,
    );
    return (test: test, monitoring: monitoring, cache: cache);
  }

  group('DriftMeetingCache, on rows written by an earlier version', () {
    test('reads a meeting as it was written then', () async {
      final (:test, :monitoring, :cache) = await openCache();
      await test.database.run(
        'INSERT INTO $_details (owner, meeting_id, cached_at, payload) '
        'VALUES (?, ?, ?, ?)',
        [_owner, _meeting.id, at(10), _meetingWrittenBefore],
      );

      expect(
        await cache.readMeeting(_owner, _meeting.id),
        equals(ok(CacheEntry(value: _meeting, cachedAt: at(10)))),
      );
      expect(monitoring.errors, isEmpty);
    });

    test('reads a page as it was written then', () async {
      final (:test, :monitoring, :cache) = await openCache();
      await test.database.run(
        'INSERT INTO $_pages '
        '(owner, period, cursor_key, page_limit, cached_at, payload) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          _owner,
          _pageKey.period.value,
          'null',
          _pageKey.limit,
          at(10),
          _pageWrittenBefore,
        ],
      );

      expect(
        await cache.readPage(_owner, _pageKey),
        equals(
          ok(
            CacheEntry(
              value: createPage([aMeetingSummary()]),
              cachedAt: at(10),
            ),
          ),
        ),
      );
      expect(monitoring.errors, isEmpty);
    });

    test('writes what it reads: '
        'a row written now is the row written then', () async {
      final (:test, monitoring: _, :cache) = await openCache();
      await cache.saveMeeting(_owner, _meeting, at(10));
      await cache.savePage(
        _owner,
        _pageKey,
        createPage([aMeetingSummary()]),
        at(10),
      );

      final meetings = await test.database.all('SELECT payload FROM $_details');
      final pages = await test.database.all('SELECT payload FROM $_pages');

      expect(meetings.first['payload'], equals(_meetingWrittenBefore));
      expect(pages.first['payload'], equals(_pageWrittenBefore));
    });
  });

  group('DriftMeetingCache, on rows that no longer read back', () {
    /// Overwrites the stored payload of the meeting, behind the back of the
    /// cache.
    Future<
      ({TestDatabase test, FakeMonitoring monitoring, DriftMeetingCache cache})
    >
    corrupt(String payload) async {
      final opened = await openCache();
      await opened.cache.saveMeeting(_owner, _meeting, at(10));
      await opened.test.database.run('UPDATE $_details SET payload = ?', [
        payload,
      ]);
      return opened;
    }

    Future<Object?> rowsLeft(TestDatabase test) async =>
        (await test.database.all('SELECT count(*) AS total FROM $_details'))
            .single['total'];

    Map<String, Object?> withStatus(String status) {
      final stored = _storedMeeting();
      for (final item in stored['agenda']! as List<Object?>) {
        final resolution = (item! as Map<String, Object?>)['resolution'];
        if (resolution != null) {
          (resolution as Map<String, Object?>)['status'] = status;
        }
      }
      return stored;
    }

    final payloads = <(String, String)>[
      ('text that is not JSON', 'not json at all'),
      (
        'JSON that is not the shape of a meeting',
        jsonEncode({'id': 'meeting-1'}),
      ),
      ('a meeting whose status is not one', jsonEncode(withStatus('archived'))),
      (
        'a meeting with a blank title',
        jsonEncode({..._storedMeeting(), 'title': '   '}),
      ),
    ];
    for (final (name, payload) in payloads) {
      test('reads $name as a miss, reports it, and deletes the row', () async {
        final (:test, :monitoring, :cache) = await corrupt(payload);

        expect(
          await cache.readMeeting(_owner, _meeting.id),
          equals(ok<CacheEntry<Object?>?>(null)),
        );

        expect(
          monitoring.capturedEvents(),
          equals([MonitoringEvent.storedRowDiscarded]),
        );
        expect(await rowsLeft(test), equals(0));
      });
    }

    test('cannot be made to hold a payload that is NULL: '
        'the database refuses it', () async {
      final (:test, monitoring: _, :cache) = await openCache();
      await cache.saveMeeting(_owner, _meeting, at(10));

      await expectLater(
        test.database.run('UPDATE $_details SET payload = NULL'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('reads a cached instant that is not an instant as a miss', () async {
      final (:test, :monitoring, :cache) = await openCache();
      await cache.saveMeeting(_owner, _meeting, at(10));
      await test.database.run('UPDATE $_details SET cached_at = -5');

      expect(
        await cache.readMeeting(_owner, _meeting.id),
        equals(ok<CacheEntry<Object?>?>(null)),
      );

      expect(
        monitoring.capturedEvents(),
        equals([MonitoringEvent.storedRowDiscarded]),
      );
      expect(await rowsLeft(test), equals(0));
    });

    test('reports the places the payload broke the schema, '
        'never what it held', () async {
      final wire = {
        ..._storedMeeting(),
        'title': 'A secret title',
        'scheduledAt': 'yesterday-ish',
      };
      final (test: _, :monitoring, :cache) = await corrupt(jsonEncode(wire));

      await cache.readMeeting(_owner, _meeting.id);

      expect(
        monitoring.errors.single.attributes,
        equals({
          LogAttribute.resource: 'meeting',
          LogAttribute.issuePaths: 'scheduledAt',
        }),
      );
      expect('${monitoring.errors}', isNot(contains('A secret title')));
      expect('${monitoring.errors}', isNot(contains('yesterday-ish')));
    });

    test('reads a page that no longer passes as a miss, '
        'reports it, and deletes the row', () async {
      final (:test, :monitoring, :cache) = await openCache();
      await cache.savePage(
        _owner,
        _pageKey,
        createPage([aMeetingSummary()]),
        at(10),
      );
      await test.database.run('UPDATE $_pages SET payload = ?', [
        '{"items":3}',
      ]);

      expect(
        await cache.readPage(_owner, _pageKey),
        equals(ok<CacheEntry<Object?>?>(null)),
      );

      expect(monitoring.errors.map((captured) => captured.attributes), [
        {
          LogAttribute.resource: 'meetingPage',
          LogAttribute.issuePaths: 'items',
        },
      ]);
      expect(await test.database.all('SELECT * FROM $_pages'), isEmpty);
    });

    test('still returns the miss when the row cannot be deleted', () async {
      final (:test, monitoring: _, :cache) = await corrupt('not json at all');
      // The read finds the row, then the delete that follows fails.
      test.faults.failWhileMatching(RegExp('^DELETE'));

      expect(
        await cache.readMeeting(_owner, _meeting.id),
        equals(ok<CacheEntry<Object?>?>(null)),
      );
    });

    test('keeps a good row next to a corrupted one', () async {
      final (:test, monitoring: _, :cache) = await corrupt('not json at all');
      final other = aMeeting(
        summary: aMeetingSummary(id: aMeetingId('meeting-2')),
      );
      await cache.saveMeeting(_owner, other, at(11));

      await cache.readMeeting(_owner, _meeting.id);

      expect(
        await cache.readMeeting(_owner, other.id),
        equals(ok(CacheEntry(value: other, cachedAt: at(11)))),
      );
      expect(await rowsLeft(test), equals(1));
    });
  });

  group('DriftMeetingCache, on a storage that does not answer', () {
    test('turns every call into a storage error '
        'within the time it was given', () async {
      final test = await openTestDatabase();
      final cache = DriftMeetingCache(
        database: test.database,
        monitoring: FakeMonitoring(),
        timeoutMillis: 20,
      );
      test.faults.hang(true);

      final answers = await Future.wait<Result<Object?, AppError>>([
        cache.readMeeting(_owner, _meeting.id),
        cache.readPage(_owner, _pageKey),
        cache.saveMeeting(_owner, _meeting, at(1)),
        cache.removeMeeting(_owner, _meeting.id),
        cache.purge(),
      ]);

      expect([
        for (final answer in answers)
          switch (answer) {
            Err(:final error) => (error as dynamic).cause,
            Ok() => null,
          },
      ], equals(['timeout', 'timeout', 'timeout', 'timeout', 'timeout']));
    });

    test(
      'puts no statement, value or path in the cause of a failure',
      () async {
        final test = await openTestDatabase();
        final cache = DriftMeetingCache(
          database: test.database,
          monitoring: FakeMonitoring(),
        );
        await test.database.run('DROP TABLE $_details');

        final failed = await cache.readMeeting(_owner, _meeting.id);

        expect(failed, equals(err(storageReadFailed('sqlite error 1'))));
        expect('$failed', isNot(contains(_details)));
      },
    );
  });

  group('the tables of DriftMeetingCache', () {
    test('hold one row per owner and key, '
        'with the key in separate columns', () async {
      final (:test, monitoring: _, :cache) = await openCache();
      await cache.saveMeeting(_owner, _meeting, at(1));
      await cache.saveMeeting(_owner, _meeting, at(2));
      await cache.saveMeeting(aUserId('owner-2'), _meeting, at(3));
      await cache.savePage(_owner, _pageKey, createPage([]), at(4));
      await cache.savePage(
        _owner,
        MeetingPageKey(
          period: _pageKey.period,
          limit: _pageKey.limit,
          cursor: unwrap(parsePageCursor('c')),
        ),
        createPage([]),
        at(5),
      );

      final details = await test.database.all(
        'SELECT owner, meeting_id FROM $_details ORDER BY owner',
      );
      final pages = await test.database.all(
        'SELECT cursor_key FROM $_pages ORDER BY cursor_key',
      );

      expect(details, [
        {'owner': 'owner-1', 'meeting_id': 'meeting-1'},
        {'owner': 'owner-2', 'meeting_id': 'meeting-1'},
      ]);
      expect([for (final row in pages) row['cursor_key']], ['"c"', 'null']);
    });

    test('keep the pages of the two periods apart', () async {
      final (test: _, monitoring: _, :cache) = await openCache();
      const past = MeetingPageKey(period: MeetingPeriod.past, limit: 10);
      await cache.savePage(_owner, _pageKey, createPage([]), at(1));

      expect(
        await cache.readPage(_owner, past),
        equals(ok<CacheEntry<Object?>?>(null)),
      );
    });
  });
}
