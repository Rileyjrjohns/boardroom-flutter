import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/application/offline/load_with_cache_fallback.dart';
import 'package:boardroom/core/application/offline/loaded.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/page.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/features/auth/application/session/require_session.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_repository.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';

/// What [ListMeetings] needs, on top of what the cache fallback needs.
abstract interface class ListMeetingsDeps implements CacheFallbackDeps {
  /// The remote meetings.
  MeetingRepository get meetings;

  /// The local cache of meetings.
  @override
  MeetingCache get meetingCache;
}

/// What a meeting listing fails with: a [SessionRequiredError], a
/// [SessionChangedError] or a [GatewayError].
typedef ListMeetingsError = AppError;

/// One page of the upcoming or the past meetings, for the first load, the pull
/// to refresh and the pagination alike. The server decides which meetings are
/// upcoming and which are past.
///
/// Requires a valid session: the cache belongs to the signed-in user, and
/// nothing is read without knowing who asks. Follows the offline policy of
/// [loadWithCacheFallback]: fresh data from the server and written through to
/// the cache, or, when there is no network, the cached page flagged stale (if
/// it is not too old). A refusal of the session (`unauthorized`) empties both
/// caches. If the user changed while the request was in flight, nothing is
/// written and the answer is `sessionChanged`. A locked app answers `appLocked`
/// (see `AppLock`).
final class ListMeetings {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final ListMeetingsDeps _deps;

  /// Lists the page [request] of the meetings of [period]: the upcoming ones
  /// or the past ones.
  Future<Result<Loaded<Page<MeetingSummary>>, ListMeetingsError>> execute({
    required MeetingPeriod period,
    required PageRequest request,
  }) async {
    final ListMeetingsDeps(:meetings, :meetingCache) = _deps;

    final UserId owner;
    switch (await requireSession(_deps)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        owner = value.user.id;
    }

    final key = MeetingPageKey(
      period: period,
      cursor: request.cursor,
      limit: request.limit,
    );

    return await loadWithCacheFallback<Page<MeetingSummary>, GatewayError>(
      _deps,
      owner,
      CacheFallbackSource(
        resource: CacheResource.meetingPage,
        attributes: {LogAttribute.period: period.value},
        fetch: () => meetings.list(period, request),
        save: (page, cachedAt) =>
            meetingCache.savePage(owner, key, page, cachedAt),
        read: () => meetingCache.readPage(owner, key),
        remove: () => meetingCache.removePage(owner, key),
        revoke: () => meetingCache.removePage(owner, key),
      ),
    );
  }
}
