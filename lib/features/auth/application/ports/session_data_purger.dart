import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';

/// Data a session leaves on the device, purged when the session ends.
///
/// The session is the business of `auth`, what a user sees and keeps is the
/// business of the other features. So `auth` states the rule ("nothing a user
/// saw stays on the device once the session is over") and declares this port;
/// each feature that keeps data for a user implements it, and the composition
/// hands the list of them to the use cases (see `purgeCaches`). A feature added
/// later joins the list without `auth` changing.
///
/// Contract: `purge` never throws, removes the data of every owner, and
/// succeeds when there is none. It settles in bounded time.
abstract interface class SessionDataPurger {
  /// What this purger empties, as the monitoring names it when the purge fails.
  CacheResource get resource;

  /// Removes everything this purger is responsible for, for every owner.
  Future<Result<void, StorageWriteFailedError>> purge();
}
