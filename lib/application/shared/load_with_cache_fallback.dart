import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/ports/types/cache_entry.dart';
import 'package:boardroom/application/shared/cache_resource.dart';
import 'package:boardroom/application/shared/end_session.dart';
import 'package:boardroom/application/shared/loaded.dart';
import 'package:boardroom/application/shared/purge_caches.dart';
import 'package:boardroom/application/shared/require_session.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/policies/cache_age.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/instant.dart';

/// What [loadWithCacheFallback] needs, on top of what the session guard needs.
abstract interface class CacheFallbackDeps implements RequireSessionDeps {
  /// Configuration, set once by the composition root: how old a cached entry
  /// may be and still be served as stale data. An older entry counts as a miss.
  DurationMillis get maxCacheAge;
}

/// The remote read of a piece of data, and the cache that mirrors it (for one
/// owner).
final class CacheFallbackSource<T, E extends RepositoryError> {
  /// Creates a source.
  const new({
    required this.resource,
    required this.attributes,
    required this.fetch,
    required this.save,
    required this.read,
    required this.remove,
    required this.revoke,
  });

  /// What is being cached.
  final CacheResource resource;

  /// Identifies the data in the logs.
  final LogAttributes attributes;

  /// Reads the remote source.
  final Future<Result<T, E>> Function() fetch;

  /// Writes the value to the cache, with the instant it is cached at.
  final Future<Result<void, StorageWriteFailedError>> Function(
    T value,
    Instant cachedAt,
  )
  save;

  /// Reads the cache.
  final Future<Result<CacheEntry<T>?, StorageReadFailedError>> Function() read;

  /// Drops this entry and nothing else. Used when the entry could not be
  /// refreshed.
  final Future<Result<void, StorageWriteFailedError>> Function() remove;

  /// Drops this entry and what hangs off it, because the server no longer lets
  /// the user have the item: a meeting takes the documents it lists with it.
  /// Used on `forbidden` and `notFound`.
  final Future<Result<void, StorageError>> Function() revoke;
}

/// The offline policy of the app, in one place. It is business logic, so it
/// lives in the application layer and not in an adapter, where it would be
/// invisible and untested.
///
/// 1. Read the remote source. Then check that the user it was read for is still
///    the one signed in (and the app still unlocked): a request can take long,
///    and a sign-out and a sign-in can fall in the middle of it. If somebody
///    else is signed in now, nothing is written, nothing is returned, and the
///    answer is `sessionChanged`. If the remote call had succeeded, what it may
///    have left on the device (the file of a downloaded document, which no
///    entry points at) is removed by emptying both caches, unless the answer is
///    `appLocked`: the user is the same and comes back.
/// 2. On success, write the data through to the cache and return it `Fresh`. A
///    cache that cannot be written does not fail the call: the failure is
///    captured, the fresh data is returned, and the entry is removed (a copy
///    that could not be refreshed must not stay readable as if it were
///    current), with a full purge if even that fails.
/// 3. When the remote source is unreachable (`networkUnavailable`, and only
///    that), read the cache and return what it holds `Stale`, with the instant
///    it was cached. A cache that cannot be read is captured and treated as a
///    miss. On a miss the original network error is returned. An entry older
///    than `maxCacheAge`, or dated in the future, counts as a miss (see
///    [isWithinMaxAge]).
/// 4. `unauthorized` means the session is no longer valid, for anything: the
///    session is ended on the device ([endRefusedSession]: the app is locked,
///    both caches are emptied for every owner, and the user is signed out, so
///    that a restart does not restore it). `forbidden` and `notFound` concern
///    one item: it is dropped from the cache with what hangs off it (`revoke`).
///    A removal that fails is captured and falls back on the full purge, so
///    that a copy the server refused is never served afterwards; a purge that
///    fails is captured. The error is returned in every case, and the cache is
///    never read.
/// 5. Any other error (`unexpected`) is returned as is, and the cache is left
///    alone.
///
/// The failure is the error of the source ([RepositoryError]), a
/// [SessionRequiredError] or a [SessionChangedError].
///
/// Known limit: pages of a list that were cached are not walked. A page that
/// shows the title of a meeting that became forbidden keeps showing it until it
/// is refreshed or expires; opening the meeting is refused, and its detail and
/// documents are gone.
Future<Result<Loaded<T>, AppError>>
loadWithCacheFallback<T, E extends RepositoryError>(
  CacheFallbackDeps deps,
  UserId owner,
  CacheFallbackSource<T, E> source,
) async {
  final CacheFallbackDeps(:clock, :monitoring, :maxCacheAge) = deps;
  final attributes = <LogAttribute, Object>{
    ...source.attributes,
    LogAttribute.resource: source.resource.value,
  };

  final remote = await source.fetch();

  final stillSignedIn = await requireSameUser(deps, owner);
  if (stillSignedIn case Err(:final error)) {
    // A source can keep what it fetched before this function sees it (the
    // repository of the documents writes the file as soon as the download is
    // complete), and nothing points at it: no entry is saved. Nobody must be
    // left with it, so both caches are emptied, the files of the documents with
    // them. Not when the app is only locked: the user is still the one who
    // asked, and the cache they have is theirs. A failed remote call kept
    // nothing.
    if (remote is Ok<T, E> &&
        error.code != AuthenticationErrorCode.appLocked.value) {
      await purgeCaches(deps);
    }
    return err(error);
  }

  switch (remote) {
    case Ok(:final value):
      final loadedAt = clock.now();
      final saved = await source.save(value, loadedAt);
      if (saved case Err(:final error)) {
        monitoring.captureError(
          MonitoringEvent.cacheWriteFailed,
          error,
          attributes,
        );
        await _dropOrPurge(deps, source.remove, attributes);
      }
      return ok(
        Loaded<T>(
          data: value,
          source: const DataSource.fresh(),
          loadedAt: loadedAt,
        ),
      );

    case Err(:final error):
      final code = error.code;
      if (code == RepositoryErrorCode.unauthorized.value) {
        await endRefusedSession(deps, owner);
        return err(error);
      }
      if (code == RepositoryErrorCode.forbidden.value ||
          code == RepositoryErrorCode.notFound.value) {
        await _dropOrPurge(deps, source.revoke, attributes);
        return err(error);
      }
      if (code != RepositoryErrorCode.networkUnavailable.value) {
        return err(error);
      }

      final CacheEntry<T>? entry;
      switch (await source.read()) {
        case Err(error: final readError):
          monitoring.captureError(
            MonitoringEvent.cacheReadFailed,
            readError,
            attributes,
          );
          return err(error);
        case Ok(:final value):
          entry = value;
      }
      if (entry == null) {
        return err(error);
      }

      final loadedAt = clock.now();
      if (!isWithinMaxAge(entry.cachedAt, loadedAt, maxCacheAge)) {
        monitoring.log(
          LogLevel.warn,
          MonitoringEvent.cacheEntryDiscarded,
          attributes,
        );
        return err(error);
      }

      // Expected behaviour, not a problem: information, so that it does not
      // raise a warning toast.
      monitoring.log(
        LogLevel.info,
        MonitoringEvent.servedFromCache,
        attributes,
      );
      return ok(
        Loaded<T>(
          data: entry.value,
          source: DataSource.stale(cachedAt: entry.cachedAt),
          loadedAt: loadedAt,
        ),
      );
  }
}

/// Drops a copy that must not be served any more. A removal that fails is
/// captured and falls back on emptying both caches, which captures its own
/// failures: the copy is never left behind with nobody told.
Future<void> _dropOrPurge(
  CacheFallbackDeps deps,
  Future<Result<void, StorageError>> Function() drop,
  LogAttributes attributes,
) async {
  final dropped = await drop();
  if (dropped case Err(:final error)) {
    deps.monitoring.captureError(
      MonitoringEvent.cacheRemoveFailed,
      error,
      attributes,
    );
    await purgeCaches(deps);
  }
}
