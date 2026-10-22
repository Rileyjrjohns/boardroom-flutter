import 'dart:async';
import 'dart:convert';

import 'package:boardroom/application/ports/meeting_cache.dart';
import 'package:boardroom/application/ports/types/cache_entry.dart';
import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/shared/validation.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/meeting_period.dart';
import 'package:boardroom/domain/value_objects/page.dart';
import 'package:boardroom/domain/value_objects/page_cursor.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import 'support.dart';

/// What the suite needs besides the port: a way to make the store refuse writes
/// (a full disk, a database that is locked) and to let it write again.
final class MeetingCacheHarness {
  /// Creates a harness.
  const new({
    required this.cache,
    required this.breakWrites,
    required this.repairWrites,
    this.failNextStatement,
    this.reopen,
  });

  /// The adapter under test.
  final MeetingCache cache;

  /// From now on every `savePage` and `saveMeeting` fails with a storage error.
  final void Function() breakWrites;

  /// Lets the store write again.
  final void Function() repairWrites;

  /// Makes the next statement the store sends to its storage fail, once. Only a
  /// store that has a storage to fail provides it
  /// (`StoreContractOptions.failsStatements`).
  final void Function()? failNextStatement;

  /// Closes the store and opens it again on the same storage, as a new start of
  /// the app would, and returns the new one. Only a store whose content
  /// survives provides it (`StoreContractOptions.survivesReopen`).
  final Future<MeetingCache> Function()? reopen;
}

/// Makes a harness, now or later.
typedef MeetingCacheFactory = FutureOr<MeetingCacheHarness> Function();

final UserId _owner = aUserId('owner-1');
final UserId _otherOwner = aUserId('owner-2');

const _pageKey = MeetingPageKey(period: MeetingPeriod.upcoming, limit: 20);

final Meeting _meeting = aMeeting();
final Meeting _otherMeeting = aMeeting(
  summary: aMeetingSummary(
    id: aMeetingId('meeting-2'),
    title: 'Audit committee',
  ),
);

final Page<MeetingSummary> _page = createPage([
  aMeetingSummary(),
  aMeetingSummary(id: aMeetingId('meeting-2'), title: 'Audit committee'),
], unwrap(parsePageCursor('meeting-2')));
final Page<MeetingSummary> _otherPage = createPage([
  aMeetingSummary(id: aMeetingId('meeting-9')),
]);

/// What a cache answers for a meeting it holds.
Ok<CacheEntry<Meeting>, Never> _meetingEntry(Meeting meeting, int cachedAt) =>
    ok(CacheEntry<Meeting>(value: meeting, cachedAt: at(cachedAt)));

/// What a cache answers for a page it holds.
Ok<CacheEntry<Page<MeetingSummary>>, Never> _pageEntry(
  Page<MeetingSummary> page,
  int cachedAt,
) => ok(CacheEntry<Page<MeetingSummary>>(value: page, cachedAt: at(cachedAt)));

/// Tries to change a meeting in place, at every depth the lists allow, the way
/// a careless caller could. The values are immutable and their lists
/// unmodifiable, so every attempt is refused.
void _deface(Meeting meeting) {
  expectRefused(() => meeting.agenda.clear());
  expectRefused(() => meeting.documents.clear());
}

/// The contract of `MeetingCache`, as a suite any implementation runs.
/// Everything it checks is written in the port: owners are kept apart, a miss
/// is a value, `save` replaces, `remove` and `purge` succeed when there is
/// nothing to remove, and the store keeps no reference to the objects that go
/// in or out. The factory returns a fresh, empty cache.
void describeMeetingCacheContract(
  String name,
  MeetingCacheFactory createCache,
  StoreContractOptions options,
) {
  group('$name honours the MeetingCache contract', () {
    late MeetingCacheHarness harness;
    late MeetingCache cache;

    setUp(() async {
      harness = await createCache();
      cache = harness.cache;
    });

    test(
      'answers a miss with a successful undefined, never an error',
      () async {
        expect(
          await cache.readMeeting(_owner, _meeting.id),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );
        expect(
          await cache.readPage(_owner, _pageKey),
          equals(ok<CacheEntry<Page<MeetingSummary>>?>(null)),
        );
      },
    );

    test('gives back a meeting as it was saved, '
        'with the instant it was saved at', () async {
      expect(
        await cache.saveMeeting(_owner, _meeting, at(10)),
        equals(ok<void>(null)),
      );

      expect(
        await cache.readMeeting(_owner, _meeting.id),
        equals(_meetingEntry(_meeting, 10)),
      );
    });

    test('gives back a page as it was saved, with its cursor, '
        'or without one on the last page', () async {
      final lastPage = createPage([aMeetingSummary()]);
      await cache.savePage(_owner, _pageKey, _page, at(20));
      await cache.savePage(
        _owner,
        _pageKey.copyWith(period: MeetingPeriod.past),
        lastPage,
        at(21),
      );

      expect(
        await cache.readPage(_owner, _pageKey),
        equals(_pageEntry(_page, 20)),
      );
      expect(
        await cache.readPage(
          _owner,
          _pageKey.copyWith(period: MeetingPeriod.past),
        ),
        equals(_pageEntry(lastPage, 21)),
      );
    });

    test('replaces what is stored under the same owner and key, '
        'and the instant with it', () async {
      await cache.saveMeeting(_owner, _meeting, at(10));
      await cache.saveMeeting(
        _owner,
        _meeting.copyWith(title: 'Renamed'),
        at(11),
      );
      await cache.savePage(_owner, _pageKey, _page, at(20));
      await cache.savePage(_owner, _pageKey, _otherPage, at(21));

      expect(
        await cache.readMeeting(_owner, _meeting.id),
        equals(_meetingEntry(_meeting.copyWith(title: 'Renamed'), 11)),
      );
      expect(
        await cache.readPage(_owner, _pageKey),
        equals(_pageEntry(_otherPage, 21)),
      );
    });

    test('tells meetings apart by id', () async {
      await cache.saveMeeting(_owner, _meeting, at(10));
      await cache.saveMeeting(_owner, _otherMeeting, at(11));

      expect(
        await cache.readMeeting(_owner, _otherMeeting.id),
        equals(_meetingEntry(_otherMeeting, 11)),
      );
      expect(
        await cache.readMeeting(_owner, aMeetingId('meeting-3')),
        equals(ok<CacheEntry<Meeting>?>(null)),
      );
    });

    test('tells pages apart by period, by cursor and by page size', () async {
      await cache.savePage(_owner, _pageKey, _page, at(20));
      final cursor = unwrap(parsePageCursor('meeting-2'));

      for (final key in [
        _pageKey.copyWith(period: MeetingPeriod.past),
        _pageKey.copyWith(limit: 21),
        _pageKey.copyWith(cursor: cursor),
      ]) {
        expect(
          await cache.readPage(_owner, key),
          equals(ok<CacheEntry<Page<MeetingSummary>>?>(null)),
        );
      }
      await cache.savePage(
        _owner,
        _pageKey.copyWith(cursor: cursor),
        _otherPage,
        at(21),
      );
      expect(
        await cache.readPage(_owner, _pageKey),
        equals(_pageEntry(_page, 20)),
      );
    });

    test('keeps the entries of two owners apart: '
        'an owner reads a miss where another saved', () async {
      await cache.saveMeeting(_owner, _meeting, at(10));
      await cache.savePage(_owner, _pageKey, _page, at(20));

      expect(
        await cache.readMeeting(_otherOwner, _meeting.id),
        equals(ok<CacheEntry<Meeting>?>(null)),
      );
      expect(
        await cache.readPage(_otherOwner, _pageKey),
        equals(ok<CacheEntry<Page<MeetingSummary>>?>(null)),
      );
    });

    test('does not let one owner overwrite, '
        'or remove, the entry of another', () async {
      await cache.saveMeeting(_owner, _meeting, at(10));
      await cache.savePage(_owner, _pageKey, _page, at(20));
      await cache.saveMeeting(_otherOwner, _otherMeeting, at(11));
      await cache.saveMeeting(
        _otherOwner,
        _meeting.copyWith(title: 'Theirs'),
        at(12),
      );
      await cache.savePage(_otherOwner, _pageKey, _otherPage, at(21));

      await cache.removeMeeting(_otherOwner, _meeting.id);
      await cache.removePage(_otherOwner, _pageKey);

      expect(
        await cache.readMeeting(_owner, _meeting.id),
        equals(_meetingEntry(_meeting, 10)),
      );
      expect(
        await cache.readPage(_owner, _pageKey),
        equals(_pageEntry(_page, 20)),
      );
      expect(
        await cache.readMeeting(_otherOwner, _otherMeeting.id),
        equals(_meetingEntry(_otherMeeting, 11)),
      );
    });

    test('removes one entry and leaves the others, '
        'and succeeds when the entry is absent', () async {
      await cache.saveMeeting(_owner, _meeting, at(10));
      await cache.saveMeeting(_owner, _otherMeeting, at(11));
      await cache.savePage(_owner, _pageKey, _page, at(20));
      await cache.savePage(
        _owner,
        _pageKey.copyWith(limit: 5),
        _otherPage,
        at(21),
      );

      expect(
        await cache.removeMeeting(_owner, _meeting.id),
        equals(ok<void>(null)),
      );
      expect(
        await cache.removeMeeting(_owner, _meeting.id),
        equals(ok<void>(null)),
      );
      expect(await cache.removePage(_owner, _pageKey), equals(ok<void>(null)));
      expect(await cache.removePage(_owner, _pageKey), equals(ok<void>(null)));
      expect(
        await cache.removeMeeting(_otherOwner, _meeting.id),
        equals(ok<void>(null)),
      );

      expect(
        await cache.readMeeting(_owner, _meeting.id),
        equals(ok<CacheEntry<Meeting>?>(null)),
      );
      expect(
        await cache.readPage(_owner, _pageKey),
        equals(ok<CacheEntry<Page<MeetingSummary>>?>(null)),
      );
      expect(
        await cache.readMeeting(_owner, _otherMeeting.id),
        equals(_meetingEntry(_otherMeeting, 11)),
      );
      expect(
        await cache.readPage(_owner, _pageKey.copyWith(limit: 5)),
        equals(_pageEntry(_otherPage, 21)),
      );
    });

    test('purges every entry of every owner, '
        'and succeeds when there is none', () async {
      expect(await cache.purge(), equals(ok<void>(null)));
      await cache.saveMeeting(_owner, _meeting, at(10));
      await cache.saveMeeting(_otherOwner, _otherMeeting, at(11));
      await cache.savePage(_owner, _pageKey, _page, at(20));
      await cache.savePage(_otherOwner, _pageKey, _otherPage, at(21));

      expect(await cache.purge(), equals(ok<void>(null)));

      for (final owner in [_owner, _otherOwner]) {
        expect(
          await cache.readMeeting(owner, _meeting.id),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );
        expect(
          await cache.readMeeting(owner, _otherMeeting.id),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );
        expect(
          await cache.readPage(owner, _pageKey),
          equals(ok<CacheEntry<Page<MeetingSummary>>?>(null)),
        );
      }
      expect(await cache.purge(), equals(ok<void>(null)));
    });

    test('can be used again after a purge', () async {
      await cache.saveMeeting(_owner, _meeting, at(10));
      await cache.purge();
      await cache.saveMeeting(_owner, _meeting, at(30));

      expect(
        await cache.readMeeting(_owner, _meeting.id),
        equals(_meetingEntry(_meeting, 30)),
      );
    });

    group('a save that fails', () {
      test('does not leave the older meeting readable '
          'as if it were current', () async {
        await cache.saveMeeting(_owner, _meeting, at(10));
        harness.breakWrites();

        final failed = await cache.saveMeeting(
          _owner,
          _meeting.copyWith(title: 'Newer'),
          at(11),
        );
        harness.repairWrites();

        expect(isOk(failed), isFalse);
        expect(errorCodeOf(failed), equals(StorageErrorCode.writeFailed.value));
        expect(
          await cache.readMeeting(_owner, _meeting.id),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );
      });

      test('does not leave the older page readable '
          'as if it were current', () async {
        await cache.savePage(_owner, _pageKey, _page, at(20));
        harness.breakWrites();

        final failed = await cache.savePage(
          _owner,
          _pageKey,
          _otherPage,
          at(21),
        );
        harness.repairWrites();

        expect(isOk(failed), isFalse);
        expect(
          await cache.readPage(_owner, _pageKey),
          equals(ok<CacheEntry<Page<MeetingSummary>>?>(null)),
        );
      });

      test('leaves the other entries, '
          'and the entries of other owners, alone', () async {
        await cache.saveMeeting(_owner, _otherMeeting, at(10));
        await cache.saveMeeting(_otherOwner, _meeting, at(11));
        await cache.saveMeeting(_owner, _meeting, at(12));
        harness.breakWrites();

        await cache.saveMeeting(
          _owner,
          _meeting.copyWith(title: 'Newer'),
          at(13),
        );
        harness.repairWrites();

        expect(
          await cache.readMeeting(_owner, _otherMeeting.id),
          equals(_meetingEntry(_otherMeeting, 10)),
        );
        expect(
          await cache.readMeeting(_otherOwner, _meeting.id),
          equals(_meetingEntry(_meeting, 11)),
        );
      });

      test('saves again once the store works', () async {
        harness.breakWrites();
        await cache.saveMeeting(_owner, _meeting, at(10));
        harness.repairWrites();

        expect(
          await cache.saveMeeting(_owner, _meeting, at(11)),
          equals(ok<void>(null)),
        );
        expect(
          await cache.readMeeting(_owner, _meeting.id),
          equals(_meetingEntry(_meeting, 11)),
        );
      });
    });

    group('the storage key is injective in the owner and the id', () {
      Meeting meetingOf(String id, String title) => aMeeting(
        summary: aMeetingSummary(id: aMeetingId(id), title: title),
      );

      test('never mixes up two pairs of (owner, meeting id), '
          'whatever characters they contain', () async {
        final pairs = [
          for (final owner in trickyIds)
            for (final id in trickyIds) (owner, id),
        ];
        for (final (owner, id) in pairs) {
          await cache.saveMeeting(
            aUserId(owner),
            meetingOf(id, jsonEncode([owner, id])),
            at(1),
          );
        }

        for (final (owner, id) in pairs) {
          final read = await cache.readMeeting(aUserId(owner), aMeetingId(id));
          expect(valueOf(read)?.value.title, equals(jsonEncode([owner, id])));
        }
      });

      test('never mixes up two pairs of (owner, cursor), '
          'whatever characters they contain', () async {
        // A cursor is trimmed by the domain, so those that differ only by
        // their edges are one cursor.
        final cursors = trickyIds.where((cursor) => trimText(cursor) == cursor);
        final pairs = [
          for (final owner in trickyIds)
            for (final cursor in cursors) (owner, cursor),
        ];
        MeetingPageKey keyOf(String cursor) =>
            _pageKey.copyWith(cursor: unwrap(parsePageCursor(cursor)));
        for (final (owner, cursor) in pairs) {
          final page = createPage([
            aMeetingSummary(title: jsonEncode([owner, cursor])),
          ]);
          await cache.savePage(aUserId(owner), keyOf(cursor), page, at(1));
        }

        for (final (owner, cursor) in pairs) {
          final read = await cache.readPage(aUserId(owner), keyOf(cursor));
          expect(
            valueOf(read)?.value.items.first.title,
            equals(jsonEncode([owner, cursor])),
          );
        }
      });

      test('does not merge an owner with a prefix of another, '
          'nor a meeting id with a prefix of another', () async {
        await cache.saveMeeting(
          aUserId('owner'),
          meetingOf('meeting', 'short'),
          at(1),
        );
        await cache.saveMeeting(
          aUserId('owner-2'),
          meetingOf('meeting', 'owner-2'),
          at(1),
        );
        await cache.saveMeeting(
          aUserId('owner'),
          meetingOf('meeting-2', 'longer'),
          at(1),
        );

        final read = await cache.readMeeting(
          aUserId('owner'),
          aMeetingId('meeting'),
        );

        expect(valueOf(read)?.value.title, equals('short'));
      });
    });

    // A store without a storage to fail, or with nothing to reopen, skips
    // these: they show as skipped.
    group('a statement that fails', () {
      void failNext() {
        final fail = harness.failNextStatement;
        if (fail == null) {
          throw StateError('The harness cannot fail a statement.');
        }
        fail();
      }

      test('turns a read that fails into a storage error, '
          'and finds the entry again afterwards', () async {
        await cache.saveMeeting(_owner, _meeting, at(10));
        await cache.savePage(_owner, _pageKey, _page, at(20));

        failNext();
        final failedMeeting = await cache.readMeeting(_owner, _meeting.id);
        failNext();
        final failedPage = await cache.readPage(_owner, _pageKey);

        expect(
          errorCodeOf(failedMeeting),
          equals(StorageErrorCode.readFailed.value),
        );
        expect(
          errorCodeOf(failedPage),
          equals(StorageErrorCode.readFailed.value),
        );
        expect(
          await cache.readMeeting(_owner, _meeting.id),
          equals(_meetingEntry(_meeting, 10)),
        );
        expect(
          await cache.readPage(_owner, _pageKey),
          equals(_pageEntry(_page, 20)),
        );
      });

      test('turns a save that fails into a storage error, '
          'and leaves no older entry readable', () async {
        await cache.saveMeeting(_owner, _meeting, at(10));
        await cache.savePage(_owner, _pageKey, _page, at(20));
        await cache.saveMeeting(_owner, _otherMeeting, at(11));

        failNext();
        final failedMeeting = await cache.saveMeeting(
          _owner,
          _meeting.copyWith(title: 'Newer'),
          at(12),
        );
        failNext();
        final failedPage = await cache.savePage(
          _owner,
          _pageKey,
          _otherPage,
          at(21),
        );

        expect(
          errorCodeOf(failedMeeting),
          equals(StorageErrorCode.writeFailed.value),
        );
        expect(
          errorCodeOf(failedPage),
          equals(StorageErrorCode.writeFailed.value),
        );
        expect(
          await cache.readMeeting(_owner, _meeting.id),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );
        expect(
          await cache.readPage(_owner, _pageKey),
          equals(ok<CacheEntry<Page<MeetingSummary>>?>(null)),
        );
        expect(
          await cache.readMeeting(_owner, _otherMeeting.id),
          equals(_meetingEntry(_otherMeeting, 11)),
        );
      });

      test('turns a removal that fails into a storage error, '
          'and keeps the entry', () async {
        await cache.saveMeeting(_owner, _meeting, at(10));
        await cache.savePage(_owner, _pageKey, _page, at(20));

        failNext();
        final failedMeeting = await cache.removeMeeting(_owner, _meeting.id);
        failNext();
        final failedPage = await cache.removePage(_owner, _pageKey);

        expect(
          errorCodeOf(failedMeeting),
          equals(StorageErrorCode.writeFailed.value),
        );
        expect(
          errorCodeOf(failedPage),
          equals(StorageErrorCode.writeFailed.value),
        );
        expect(
          await cache.readMeeting(_owner, _meeting.id),
          equals(_meetingEntry(_meeting, 10)),
        );
        expect(
          await cache.readPage(_owner, _pageKey),
          equals(_pageEntry(_page, 20)),
        );
      });

      test('turns a purge that fails into a storage error, '
          'and keeps every entry, none half removed', () async {
        await cache.saveMeeting(_owner, _meeting, at(10));
        await cache.savePage(_otherOwner, _pageKey, _page, at(20));

        failNext();
        final failed = await cache.purge();

        expect(errorCodeOf(failed), equals(StorageErrorCode.writeFailed.value));
        expect(
          await cache.readMeeting(_owner, _meeting.id),
          equals(_meetingEntry(_meeting, 10)),
        );
        expect(
          await cache.readPage(_otherOwner, _pageKey),
          equals(_pageEntry(_page, 20)),
        );
        expect(await cache.purge(), equals(ok<void>(null)));
      });

      test('fails once and no more: the next call works', () async {
        failNext();
        await cache.saveMeeting(_owner, _meeting, at(10));

        expect(
          await cache.saveMeeting(_owner, _meeting, at(11)),
          equals(ok<void>(null)),
        );
        expect(
          await cache.readMeeting(_owner, _meeting.id),
          equals(_meetingEntry(_meeting, 11)),
        );
      });
    }, skip: !options.failsStatements);

    group('closed and opened again', () {
      Future<MeetingCache> reopen() {
        final reopenStore = harness.reopen;
        if (reopenStore == null) {
          throw StateError('The harness cannot reopen the store.');
        }
        return reopenStore();
      }

      test('gives back the meetings and the pages of every owner as they were, '
          'with their instants', () async {
        await cache.saveMeeting(_owner, _meeting, at(10));
        await cache.saveMeeting(_otherOwner, _otherMeeting, at(11));
        await cache.savePage(_owner, _pageKey, _page, at(20));
        await cache.savePage(
          _otherOwner,
          _pageKey.copyWith(period: MeetingPeriod.past),
          _otherPage,
          at(21),
        );

        final reopened = await reopen();

        expect(
          await reopened.readMeeting(_owner, _meeting.id),
          equals(_meetingEntry(_meeting, 10)),
        );
        expect(
          await reopened.readMeeting(_otherOwner, _otherMeeting.id),
          equals(_meetingEntry(_otherMeeting, 11)),
        );
        expect(
          await reopened.readPage(_owner, _pageKey),
          equals(_pageEntry(_page, 20)),
        );
        expect(
          await reopened.readPage(
            _otherOwner,
            _pageKey.copyWith(period: MeetingPeriod.past),
          ),
          equals(_pageEntry(_otherPage, 21)),
        );
        expect(
          await reopened.readMeeting(_otherOwner, _meeting.id),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );
      });

      test('does not give back what was removed '
          'before it was closed', () async {
        await cache.saveMeeting(_owner, _meeting, at(10));
        await cache.saveMeeting(_owner, _otherMeeting, at(11));
        await cache.savePage(_owner, _pageKey, _page, at(20));
        await cache.removeMeeting(_owner, _meeting.id);
        await cache.removePage(_owner, _pageKey);

        final reopened = await reopen();

        expect(
          await reopened.readMeeting(_owner, _meeting.id),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );
        expect(
          await reopened.readPage(_owner, _pageKey),
          equals(ok<CacheEntry<Page<MeetingSummary>>?>(null)),
        );
        expect(
          await reopened.readMeeting(_owner, _otherMeeting.id),
          equals(_meetingEntry(_otherMeeting, 11)),
        );
      });

      test('does not give back what was purged before it was closed', () async {
        await cache.saveMeeting(_owner, _meeting, at(10));
        await cache.savePage(_otherOwner, _pageKey, _page, at(20));
        await cache.purge();

        final reopened = await reopen();

        expect(
          await reopened.readMeeting(_owner, _meeting.id),
          equals(ok<CacheEntry<Meeting>?>(null)),
        );
        expect(
          await reopened.readPage(_otherOwner, _pageKey),
          equals(ok<CacheEntry<Page<MeetingSummary>>?>(null)),
        );
      });
    }, skip: !options.survivesReopen);

    group('writers at the same time', () {
      test('leaves one complete version of an entry '
          'when several saves of it run together', () async {
        final versions = [
          for (final number in [1, 2, 3, 4, 5, 6])
            CacheEntry<Meeting>(
              value: _meeting.copyWith(title: 'Version $number'),
              cachedAt: at(number),
            ),
        ];

        await Future.wait([
          for (final version in versions)
            cache.saveMeeting(_owner, version.value, version.cachedAt),
        ]);

        final read = await cache.readMeeting(_owner, _meeting.id);
        final held = valueOf(read);
        expect(versions, contains(held));
      });

      test('keeps every entry when saves of different keys '
          'run together', () async {
        final meetings = [
          for (final number in [1, 2, 3, 4, 5])
            aMeeting(summary: aMeetingSummary(id: aMeetingId('m-$number'))),
        ];
        final keys = [
          for (final limit in [5, 10, 15]) _pageKey.copyWith(limit: limit),
        ];

        await Future.wait([
          for (final (number, meeting) in meetings.indexed)
            cache.saveMeeting(_owner, meeting, at(number)),
          for (final key in keys) cache.savePage(_owner, key, _page, at(30)),
        ]);

        for (final (number, meeting) in meetings.indexed) {
          expect(
            await cache.readMeeting(_owner, meeting.id),
            equals(_meetingEntry(meeting, number)),
          );
        }
        for (final key in keys) {
          expect(
            await cache.readPage(_owner, key),
            equals(_pageEntry(_page, 30)),
          );
        }
      });

      test('leaves nothing, or one complete version, '
          'when a save, a removal and reads run together', () async {
        final answers = await Future.wait<Result<Object?, AppError>>([
          cache.saveMeeting(_owner, _meeting, at(1)),
          cache.readMeeting(_owner, _meeting.id),
          cache.removeMeeting(_owner, _meeting.id),
          cache.saveMeeting(_owner, _meeting.copyWith(title: 'Newer'), at(2)),
          cache.readMeeting(_owner, _meeting.id),
          cache.purge(),
        ]);

        expect(answers.every(isOk), isTrue);
        final read = await cache.readMeeting(_owner, _meeting.id);
        final held = valueOf(read);
        expect([null, 'Newer', _meeting.title], contains(held?.value.title));
      });
    });

    group('keeps no reference to the objects that go in or out', () {
      test('is not changed by a change of the meeting '
          'after it was saved', () async {
        final saved = aMeeting();
        await cache.saveMeeting(_owner, saved, now);

        _deface(saved);

        expect(
          await cache.readMeeting(_owner, _meeting.id),
          equals(ok(CacheEntry<Meeting>(value: _meeting, cachedAt: now))),
        );
      });

      test('is not changed by a change of the page '
          'after it was saved', () async {
        final saved = createPage([
          aMeetingSummary(),
        ], unwrap(parsePageCursor('meeting-1')));
        await cache.savePage(_owner, _pageKey, saved, now);

        expectRefused(() => saved.items.clear());

        expect(
          await cache.readPage(_owner, _pageKey),
          equals(
            ok(
              CacheEntry<Page<MeetingSummary>>(
                value: createPage([
                  aMeetingSummary(),
                ], unwrap(parsePageCursor('meeting-1'))),
                cachedAt: now,
              ),
            ),
          ),
        );
      });

      test('is not changed by a change of the meeting '
          'after it was read', () async {
        await cache.saveMeeting(_owner, _meeting, now);
        final read = await cache.readMeeting(_owner, _meeting.id);

        final entry = valueOf(read);
        if (entry != null) {
          _deface(entry.value);
        }

        expect(
          await cache.readMeeting(_owner, _meeting.id),
          equals(ok(CacheEntry<Meeting>(value: _meeting, cachedAt: now))),
        );
      });

      test('is not changed by a change of the page '
          'after it was read', () async {
        await cache.savePage(_owner, _pageKey, _page, now);
        final read = await cache.readPage(_owner, _pageKey);

        final entry = valueOf(read);
        if (entry != null) {
          expectRefused(() => entry.value.items.clear());
        }

        expect(
          await cache.readPage(_owner, _pageKey),
          equals(
            ok(CacheEntry<Page<MeetingSummary>>(value: _page, cachedAt: now)),
          ),
        );
      });
    });
  });
}
