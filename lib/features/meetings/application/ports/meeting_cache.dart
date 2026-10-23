import 'package:boardroom/core/application/ports/types/cache_entry.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/domain/value_objects/page.dart';
import 'package:boardroom/core/domain/value_objects/page_cursor.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'meeting_cache.freezed.dart';

/// Identifies a cached page of a list: the period, where the page starts (the
/// first page has no cursor) and the page size. A cursor only means something
/// with the page size that produced it, so the size is part of the key.
@freezed
abstract class MeetingPageKey with _$MeetingPageKey {
  /// Creates a key.
  const factory({
    required MeetingPeriod period,
    required int limit,
    PageCursor? cursor,
  }) = _MeetingPageKey;
}

/// The local store that lets meetings already seen be read offline.
///
/// Every entry belongs to an `owner`, the user whose session fetched it, and
/// every operation takes the owner: an entry is stored under it and found under
/// it only. Reading as another user finds nothing, by construction, so a device
/// shared by two users never shows the data of one to the other. The data of an
/// owner is removed when they sign out (`purge`).
///
/// Contract:
/// - No method throws. Only a store that cannot be read or written returns a
///   storage error. Every method settles in bounded time; a store that does not
///   answer in time is a storage error.
/// - A read that finds nothing is not an error: it returns `null` as the value
///   of a successful result (a miss).
/// - `save` replaces what is stored under the same owner and key. `remove` of
///   an absent entry succeeds. Both are idempotent.
/// - A `save` that fails must not leave an older entry readable as if it were
///   current: the older entry is removed (or never left in place) before the
///   error is returned, so the next read is a miss. The application removes the
///   entry itself after a failed write, and empties the caches when it cannot;
///   this is the rule for the adapter, which does not depend on that.
/// - `purge` removes every entry of every owner, and succeeds when there is
///   none.
/// - The storage key is injective in (owner, id): owners and ids are free text,
///   so they are encoded (JSON, length prefixes, a separate column), never
///   concatenated with a separator and never normalised (no trimming, no case
///   folding, no Unicode normalisation). Two different pairs never share an
///   entry, whatever characters they contain. The same goes for the parts of a
///   page key (period, cursor, page size).
/// - The data is at rest on the device: it lives in app-private storage,
///   excluded from backups. What is given to `save` and what is returned are
///   copies, never shared with the store.
abstract interface class MeetingCache {
  /// Stores a [page] of the list [key] for [owner], dated [cachedAt].
  Future<Result<void, StorageWriteFailedError>> savePage(
    UserId owner,
    MeetingPageKey key,
    Page<MeetingSummary> page,
    Instant cachedAt,
  );

  /// `null` when the page was never cached for this owner.
  Future<Result<CacheEntry<Page<MeetingSummary>>?, StorageReadFailedError>>
  readPage(UserId owner, MeetingPageKey key);

  /// Removes the page [key] of [owner].
  Future<Result<void, StorageWriteFailedError>> removePage(
    UserId owner,
    MeetingPageKey key,
  );

  /// Stores a [meeting] for [owner], dated [cachedAt].
  Future<Result<void, StorageWriteFailedError>> saveMeeting(
    UserId owner,
    Meeting meeting,
    Instant cachedAt,
  );

  /// `null` when the meeting was never cached for this owner.
  Future<Result<CacheEntry<Meeting>?, StorageReadFailedError>> readMeeting(
    UserId owner,
    MeetingId id,
  );

  /// Removes the meeting [id] of [owner].
  Future<Result<void, StorageWriteFailedError>> removeMeeting(
    UserId owner,
    MeetingId id,
  );

  /// Removes every entry of every owner.
  Future<Result<void, StorageWriteFailedError>> purge();
}
