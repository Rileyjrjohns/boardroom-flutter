import 'dart:async';

import 'package:boardroom/application/ports/meeting_cache.dart';
import 'package:boardroom/application/ports/types/cache_entry.dart';
import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/domain/value_objects/page.dart';

/// What a test does with a read that is held.
class HeldRead {
  /// Creates a held read.
  const new({required this.hasAnswered, required this.release});

  /// Completes once the storage has answered the read and the answer is being
  /// held back.
  final Future<void> hasAnswered;

  /// Lets the answer through to the caller.
  final void Function() release;
}

/// A cache of meetings with a slow storage in front of it, for a test of what
/// happens between two statements: once `holdNextRead` is called, the next read
/// of a meeting runs on the real cache, then waits to be released before it
/// answers. The app, meanwhile, moves on (a sign-out, say). Everything else
/// goes straight to the cache it wraps.
class HoldingMeetingCache implements MeetingCache {
  /// Wraps [_inner].
  new(this._inner);

  final MeetingCache _inner;
  ({Future<void> gate, void Function() answered})? _holding;

  /// Holds the answer of the next `readMeeting` until the returned
  /// [HeldRead.release] is called.
  HeldRead holdNextRead() {
    final gate = Completer<void>();
    final hasAnswered = Completer<void>();
    _holding = (gate: gate.future, answered: hasAnswered.complete);
    return HeldRead(hasAnswered: hasAnswered.future, release: gate.complete);
  }

  @override
  Future<Result<CacheEntry<Meeting>?, StorageReadFailedError>> readMeeting(
    UserId owner,
    MeetingId id,
  ) async {
    final answer = await _inner.readMeeting(owner, id);
    final held = _holding;
    _holding = null;
    if (held != null) {
      held.answered();
      await held.gate;
    }
    return answer;
  }

  @override
  Future<Result<void, StorageWriteFailedError>> savePage(
    UserId owner,
    MeetingPageKey key,
    Page<MeetingSummary> page,
    Instant cachedAt,
  ) => _inner.savePage(owner, key, page, cachedAt);

  @override
  Future<Result<CacheEntry<Page<MeetingSummary>>?, StorageReadFailedError>>
  readPage(UserId owner, MeetingPageKey key) => _inner.readPage(owner, key);

  @override
  Future<Result<void, StorageWriteFailedError>> removePage(
    UserId owner,
    MeetingPageKey key,
  ) => _inner.removePage(owner, key);

  @override
  Future<Result<void, StorageWriteFailedError>> saveMeeting(
    UserId owner,
    Meeting meeting,
    Instant cachedAt,
  ) => _inner.saveMeeting(owner, meeting, cachedAt);

  @override
  Future<Result<void, StorageWriteFailedError>> removeMeeting(
    UserId owner,
    MeetingId id,
  ) => _inner.removeMeeting(owner, id);

  @override
  Future<Result<void, StorageWriteFailedError>> purge() => _inner.purge();
}
