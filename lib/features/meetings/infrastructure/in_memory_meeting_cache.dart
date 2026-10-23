import 'dart:convert';

import 'package:boardroom/core/application/ports/types/cache_entry.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/domain/value_objects/page.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';

/// A meeting cache in memory, for the mock configuration and as the reference
/// the contract tests run against. Every entry belongs to its owner and is
/// found under it only. What it holds is immutable, so nobody holds a reference
/// they could change into the store. It lives as long as the process: the
/// persistent adapter is the database one.
final class InMemoryMeetingCache implements MeetingCache {
  final Map<String, CacheEntry<Page<MeetingSummary>>> _pages = {};
  final Map<String, CacheEntry<Meeting>> _meetings = {};
  StorageWriteFailedError? _writeFailure;

  /// Makes every save fail with this error while set, as a full disk would. A
  /// save that fails drops the older entry under the same key, as the port
  /// requires. For tests.
  // ignore: use_setters_to_change_properties
  void failWritesWith(StorageWriteFailedError? failure) {
    _writeFailure = failure;
  }

  @override
  Future<Result<void, StorageWriteFailedError>> savePage(
    UserId owner,
    MeetingPageKey key,
    Page<MeetingSummary> page,
    Instant cachedAt,
  ) async {
    final storageKey = _pageKey(owner, key);
    final failure = _writeFailure;
    if (failure != null) {
      _pages.remove(storageKey);
      return err(failure);
    }
    _pages[storageKey] = CacheEntry(value: page, cachedAt: cachedAt);
    return ok<void>(null);
  }

  @override
  Future<Result<CacheEntry<Page<MeetingSummary>>?, StorageReadFailedError>>
  readPage(UserId owner, MeetingPageKey key) async =>
      ok(_pages[_pageKey(owner, key)]);

  @override
  Future<Result<void, StorageWriteFailedError>> removePage(
    UserId owner,
    MeetingPageKey key,
  ) async {
    _pages.remove(_pageKey(owner, key));
    return ok<void>(null);
  }

  @override
  Future<Result<void, StorageWriteFailedError>> saveMeeting(
    UserId owner,
    Meeting meeting,
    Instant cachedAt,
  ) async {
    final storageKey = _meetingKey(owner, meeting.id);
    final failure = _writeFailure;
    if (failure != null) {
      _meetings.remove(storageKey);
      return err(failure);
    }
    _meetings[storageKey] = CacheEntry(value: meeting, cachedAt: cachedAt);
    return ok<void>(null);
  }

  @override
  Future<Result<CacheEntry<Meeting>?, StorageReadFailedError>> readMeeting(
    UserId owner,
    MeetingId id,
  ) async => ok(_meetings[_meetingKey(owner, id)]);

  @override
  Future<Result<void, StorageWriteFailedError>> removeMeeting(
    UserId owner,
    MeetingId id,
  ) async {
    _meetings.remove(_meetingKey(owner, id));
    return ok<void>(null);
  }

  @override
  Future<Result<void, StorageWriteFailedError>> purge() async {
    _pages.clear();
    _meetings.clear();
    return ok<void>(null);
  }
}

// JSON keeps the parts apart whatever characters the ids contain.
String _pageKey(UserId owner, MeetingPageKey key) =>
    jsonEncode([owner, key.period.value, key.cursor, key.limit]);

String _meetingKey(UserId owner, MeetingId id) => jsonEncode([owner, id]);
