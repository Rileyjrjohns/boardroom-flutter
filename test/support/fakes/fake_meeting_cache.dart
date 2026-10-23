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

import 'copy_plain.dart';

/// An in-memory cache that keeps the entries of each owner apart, like the
/// contract says. A miss is `ok(null)`. It keeps copies of what it is given and
/// hands back copies of what it holds.
class FakeMeetingCache implements MeetingCache {
  /// Makes the reads fail while set.
  StorageReadFailedError? readFailure;

  /// Makes the saves fail while set. Nothing new is stored, and the older entry
  /// under the same key is dropped, as the port requires: it must not stay
  /// readable as if it were current.
  StorageWriteFailedError? writeFailure;

  /// Makes `removePage` and `removeMeeting` fail while set (the entry stays).
  StorageWriteFailedError? removeFailure;

  /// Makes `purge` fail while set (the entries stay).
  StorageWriteFailedError? purgeFailure;

  /// How many times `purge` was called.
  int purgeCalls = 0;

  final Map<String, CacheEntry<Page<MeetingSummary>>> _pages = {};
  final Map<String, CacheEntry<Meeting>> _meetings = {};

  /// True when nothing is stored for anybody.
  bool isEmpty() => _pages.isEmpty && _meetings.isEmpty;

  @override
  Future<Result<void, StorageWriteFailedError>> savePage(
    UserId owner,
    MeetingPageKey key,
    Page<MeetingSummary> page,
    Instant cachedAt,
  ) async {
    final failure = writeFailure;
    if (failure != null) {
      _pages.remove(_pageKey(owner, key));
      return err(failure);
    }
    _pages[_pageKey(owner, key)] = copyPlain(
      CacheEntry(value: page, cachedAt: cachedAt),
    );
    return ok<void>(null);
  }

  @override
  Future<Result<CacheEntry<Page<MeetingSummary>>?, StorageReadFailedError>>
  readPage(UserId owner, MeetingPageKey key) async {
    final failure = readFailure;
    if (failure != null) {
      return err(failure);
    }
    return ok(copyPlain(_pages[_pageKey(owner, key)]));
  }

  @override
  Future<Result<void, StorageWriteFailedError>> removePage(
    UserId owner,
    MeetingPageKey key,
  ) async {
    final failure = removeFailure;
    if (failure != null) {
      return err(failure);
    }
    _pages.remove(_pageKey(owner, key));
    return ok<void>(null);
  }

  @override
  Future<Result<void, StorageWriteFailedError>> saveMeeting(
    UserId owner,
    Meeting meeting,
    Instant cachedAt,
  ) async {
    final failure = writeFailure;
    if (failure != null) {
      _meetings.remove(_meetingKey(owner, meeting.id));
      return err(failure);
    }
    _meetings[_meetingKey(owner, meeting.id)] = copyPlain(
      CacheEntry(value: meeting, cachedAt: cachedAt),
    );
    return ok<void>(null);
  }

  @override
  Future<Result<CacheEntry<Meeting>?, StorageReadFailedError>> readMeeting(
    UserId owner,
    MeetingId id,
  ) async {
    final failure = readFailure;
    if (failure != null) {
      return err(failure);
    }
    return ok(copyPlain(_meetings[_meetingKey(owner, id)]));
  }

  @override
  Future<Result<void, StorageWriteFailedError>> removeMeeting(
    UserId owner,
    MeetingId id,
  ) async {
    final failure = removeFailure;
    if (failure != null) {
      return err(failure);
    }
    _meetings.remove(_meetingKey(owner, id));
    return ok<void>(null);
  }

  @override
  Future<Result<void, StorageWriteFailedError>> purge() async {
    purgeCalls += 1;
    final failure = purgeFailure;
    if (failure != null) {
      return err(failure);
    }
    _pages.clear();
    _meetings.clear();
    return ok<void>(null);
  }
}

// JSON keeps the parts apart whatever characters the ids contain.
String _pageKey(UserId owner, MeetingPageKey key) =>
    jsonEncode([owner, key.period.value, key.cursor, key.limit]);

String _meetingKey(UserId owner, MeetingId id) => jsonEncode([owner, id]);
