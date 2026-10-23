import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/session_data_purger.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';

/// What the meetings leave on the device for a session (the pages of the list
/// and the meetings viewed), emptied when the session ends.
final class MeetingCachePurger implements SessionDataPurger {
  /// Creates the purger of [_cache].
  const new(this._cache);

  final MeetingCache _cache;

  @override
  CacheResource get resource => CacheResource.meeting;

  @override
  Future<Result<void, StorageWriteFailedError>> purge() => _cache.purge();
}
