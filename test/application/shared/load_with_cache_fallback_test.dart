import 'package:boardroom/application/ports/document_cache.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/ports/types/cache_entry.dart';
import 'package:boardroom/application/shared/cache_resource.dart';
import 'package:boardroom/application/shared/load_with_cache_fallback.dart';
import 'package:boardroom/application/shared/loaded.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:test/test.dart';

import '../../domain/support/builders.dart';
import '../support/create_fakes.dart';
import '../support/fake_monitoring.dart';

const String _remote = 'remote value';
const int _maxAge = 3600000;
final CacheEntry<String> _cached = CacheEntry(
  value: 'cached value',
  cachedAt: at(-60000),
);
final Map<LogAttribute, Object> _logAttributes = {
  LogAttribute.meetingId: 'meeting-1',
  LogAttribute.resource: CacheResource.meeting.value,
};

typedef _Fetch = Future<Result<String, RepositoryError>> Function();

/// A source whose operations are scripted and counted.
final class _Scripted {
  new({
    required _Fetch fetch,
    Result<CacheEntry<String>?, StorageReadFailedError>? read,
    Result<void, StorageWriteFailedError>? save,
    Result<void, StorageWriteFailedError>? remove,
    Result<void, StorageError>? revoke,
  }) {
    source = CacheFallbackSource<String, RepositoryError>(
      resource: CacheResource.meeting,
      attributes: {LogAttribute.meetingId: 'meeting-1'},
      fetch: fetch,
      save: (value, cachedAt) async {
        saved.add((value: value, cachedAt: cachedAt));
        return save ?? ok<void>(null);
      },
      read: () async {
        reads += 1;
        return read ?? ok<CacheEntry<String>?>(null);
      },
      remove: () async {
        removals += 1;
        return remove ?? ok<void>(null);
      },
      revoke: () async {
        revocations += 1;
        return revoke ?? ok<void>(null);
      },
    );
  }

  late final CacheFallbackSource<String, RepositoryError> source;
  final List<({String value, Instant cachedAt})> saved = [];
  int reads = 0;
  int removals = 0;
  int revocations = 0;
}

/// A fetch that answers [result].
_Fetch _answering(Result<String, RepositoryError> result) =>
    () async => result;

final UserId _owner = aUserId();

/// The fakes of the ports as the deps of the policy, with the maximum age of
/// the tests.
Fakes _setup() => createFakes().copyWith(maxCacheAge: aDuration(_maxAge));

void main() {
  group('loadWithCacheFallback', () {
    group('when the remote source answers', () {
      test('returns the data fresh and writes it through to the cache with the '
          'instant of the clock', () async {
        final deps = _setup();
        final scripted = _Scripted(fetch: _answering(ok(_remote)));

        final result = await loadWithCacheFallback(
          deps,
          _owner,
          scripted.source,
        );

        expect(
          result,
          equals(
            ok(
              Loaded(
                data: _remote,
                source: const DataSource.fresh(),
                loadedAt: now,
              ),
            ),
          ),
        );
        expect(scripted.saved, equals([(value: _remote, cachedAt: now)]));
        expect(deps.monitoring.errors, isEmpty);
      });

      test('stamps the data with the instant of the clock when it answers, not '
          'when it was asked', () async {
        final deps = _setup();
        final scripted = _Scripted(
          fetch: () async {
            deps.clock.advance(5000);
            return ok(_remote);
          },
        );

        final result = await loadWithCacheFallback(
          deps,
          _owner,
          scripted.source,
        );

        expect(unwrap(result).loadedAt, equals(at(5000)));
        expect(scripted.saved, equals([(value: _remote, cachedAt: at(5000))]));
      });

      test('does not read nor remove anything in the cache', () async {
        final scripted = _Scripted(fetch: _answering(ok(_remote)));

        await loadWithCacheFallback(_setup(), _owner, scripted.source);

        expect(scripted.reads, equals(0));
        expect(scripted.removals, equals(0));
      });

      test('still returns the fresh data when the cache cannot be written, and '
          'captures the failure', () async {
        final deps = _setup();
        final failure = storageWriteFailed('disk full');
        final scripted = _Scripted(
          fetch: _answering(ok(_remote)),
          save: err(failure),
        );

        final result = await loadWithCacheFallback(
          deps,
          _owner,
          scripted.source,
        );

        expect(
          result,
          equals(
            ok(
              Loaded(
                data: _remote,
                source: const DataSource.fresh(),
                loadedAt: now,
              ),
            ),
          ),
        );
        expect(
          deps.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.cacheWriteFailed,
              error: failure,
              attributes: _logAttributes,
            ),
          ]),
        );
      });
    });

    group('when the network is unavailable', () {
      test('serves the cached value flagged stale, with the instant it was '
          'cached', () async {
        final deps = _setup();
        final scripted = _Scripted(
          fetch: _answering(err(networkUnavailable())),
          read: ok(_cached),
        );

        final result = await loadWithCacheFallback(
          deps,
          _owner,
          scripted.source,
        );

        expect(
          result,
          equals(
            ok(
              Loaded(
                data: _cached.value,
                source: DataSource.stale(cachedAt: _cached.cachedAt),
                loadedAt: now,
              ),
            ),
          ),
        );
        expect(scripted.saved, isEmpty);
        expect(
          deps.monitoring.logs,
          equals([
            LogRecord(
              level: LogLevel.info,
              event: MonitoringEvent.servedFromCache,
              attributes: _logAttributes,
            ),
          ]),
        );
      });

      test('returns the network error on a cache miss', () async {
        final scripted = _Scripted(
          fetch: _answering(err(networkUnavailable())),
        );

        expect(
          await loadWithCacheFallback(_setup(), _owner, scripted.source),
          equals(err(networkUnavailable())),
        );
      });

      test(
        'returns the network error, and captures the failure, when the cache '
        'cannot be read',
        () async {
          final deps = _setup();
          final failure = storageReadFailed('corrupt');
          final scripted = _Scripted(
            fetch: _answering(err(networkUnavailable())),
            read: err(failure),
          );

          final result = await loadWithCacheFallback(
            deps,
            _owner,
            scripted.source,
          );

          expect(result, equals(err(networkUnavailable())));
          expect(
            deps.monitoring.capturedEvents(),
            equals([MonitoringEvent.cacheReadFailed]),
          );
          expect(deps.monitoring.errors.first.error, same(failure));
        },
      );

      group('the age of the cached value', () {
        _Scripted offlineWith(Instant cachedAt) => _Scripted(
          fetch: _answering(err(networkUnavailable())),
          read: ok(CacheEntry(value: _cached.value, cachedAt: cachedAt)),
        );

        test('is accepted up to the maximum age, included', () async {
          final result = await loadWithCacheFallback(
            _setup(),
            _owner,
            offlineWith(at(-_maxAge)).source,
          );

          expect(
            unwrap(result).source,
            equals(DataSource.stale(cachedAt: at(-_maxAge))),
          );
        });

        test(
          'makes the value a miss once it is older than that, and says so',
          () async {
            final deps = _setup();

            final result = await loadWithCacheFallback(
              deps,
              _owner,
              offlineWith(at(-_maxAge - 1)).source,
            );

            expect(result, equals(err(networkUnavailable())));
            expect(
              deps.monitoring.logs,
              equals([
                LogRecord(
                  level: LogLevel.warn,
                  event: MonitoringEvent.cacheEntryDiscarded,
                  attributes: _logAttributes,
                ),
              ]),
            );
          },
        );

        test(
          'makes a value dated in the future a miss, since the clock was set '
          'back',
          () async {
            final result = await loadWithCacheFallback(
              _setup(),
              _owner,
              offlineWith(at(1)).source,
            );

            expect(result, equals(err(networkUnavailable())));
          },
        );

        test('stamps the saved data with the instant of the call, which is not '
            'the instant it was cached', () async {
          final deps = _setup();
          deps.clock.advance(120000);
          final scripted = offlineWith(at(-60000));

          final result = await loadWithCacheFallback(
            deps,
            _owner,
            scripted.source,
          );

          expect(unwrap(result).loadedAt, equals(at(120000)));
          expect(
            unwrap(result).source,
            equals(DataSource.stale(cachedAt: at(-60000))),
          );
        });

        test('is measured with the clock at the moment of the call', () async {
          final deps = _setup();
          deps.auth.session = aSession(expiresAt: at(2 * _maxAge));
          final scripted = offlineWith(at(-60000));
          expect(
            await loadWithCacheFallback(deps, _owner, scripted.source),
            equals(
              ok(
                Loaded(
                  data: _cached.value,
                  source: DataSource.stale(cachedAt: at(-60000)),
                  loadedAt: now,
                ),
              ),
            ),
          );

          deps.clock.advance(_maxAge);

          expect(
            await loadWithCacheFallback(deps, _owner, scripted.source),
            equals(err(networkUnavailable())),
          );
        });
      });
    });

    group('when the remote source refuses the session (unauthorized)', () {
      test('empties both caches for every owner, returns the error, and never '
          'reads the cache', () async {
        final deps = _setup();
        await deps.meetingCache.saveMeeting(_owner, aMeeting(), now);
        await deps.meetingCache.saveMeeting(aUserId('user-2'), aMeeting(), now);
        await deps.documentCache.save(
          _owner,
          ViewableDocument(
            document: aDocument(),
            location: aDocumentLocation(),
          ),
          now,
        );
        final scripted = _Scripted(
          fetch: _answering(err(unauthorized())),
          read: ok(_cached),
        );

        expect(
          await loadWithCacheFallback(deps, _owner, scripted.source),
          equals(err(unauthorized())),
        );

        expect(deps.meetingCache.isEmpty(), isTrue);
        expect(deps.documentCache.isEmpty(), isTrue);
        expect(scripted.reads, equals(0));
        expect(scripted.removals + scripted.revocations, equals(0));
      });

      test('ends the session on the device: the user is signed out and the app '
          'is locked', () async {
        final deps = _setup();
        final scripted = _Scripted(fetch: _answering(err(unauthorized())));

        await loadWithCacheFallback(deps, _owner, scripted.source);

        expect(deps.auth.signOutCalls, equals(1));
        expect(deps.auth.session, isNull);
        expect(deps.appLock.isLocked(), isTrue);
      });

      test('captures a session that cannot be forgotten, and returns the '
          'refusal all the same', () async {
        final deps = _setup();
        deps.auth.signOutFailure = storageWriteFailed();
        final scripted = _Scripted(fetch: _answering(err(unauthorized())));

        expect(
          await loadWithCacheFallback(deps, _owner, scripted.source),
          equals(err(unauthorized())),
        );
        expect(
          deps.monitoring.capturedEvents(),
          equals([MonitoringEvent.signOutFailed]),
        );
      });

      test('does not sign out somebody else, who signed in while the request '
          'was on its way', () async {
        final deps = _setup();
        final scripted = _Scripted(
          fetch: () async {
            deps.auth.session = aSession(user: aUser(id: aUserId('user-2')));
            return err(unauthorized());
          },
        );

        final result = await loadWithCacheFallback(
          deps,
          _owner,
          scripted.source,
        );

        expect(result, equals(err(sessionChanged())));
        expect(deps.auth.signOutCalls, equals(0));
        expect(deps.auth.session, isNotNull);
      });

      test('captures a purge that fails, and returns the error', () async {
        final deps = _setup();
        deps.meetingCache.purgeFailure = storageWriteFailed();
        final scripted = _Scripted(fetch: _answering(err(unauthorized())));

        expect(
          await loadWithCacheFallback(deps, _owner, scripted.source),
          equals(err(unauthorized())),
        );
        expect(
          deps.monitoring.capturedEvents(),
          equals([MonitoringEvent.cachePurgeFailed]),
        );
      });
    });

    for (final (name, error) in <(String, RepositoryError)>[
      ('forbidden', forbidden()),
      ('not found', notFound()),
    ]) {
      group('when the remote source refuses the item ($name)', () {
        test('revokes the entry and what hangs off it, and returns the error, '
            'never reading the cache', () async {
          final deps = _setup();
          await deps.meetingCache.saveMeeting(_owner, aMeeting(), now);
          final scripted = _Scripted(
            fetch: _answering(err(error)),
            read: ok(_cached),
          );

          expect(
            await loadWithCacheFallback(deps, _owner, scripted.source),
            equals(err(error)),
          );

          expect(scripted.revocations, equals(1));
          expect(scripted.removals, equals(0));
          expect(scripted.reads, equals(0));
          expect(deps.meetingCache.isEmpty(), isFalse);
        });

        test('empties both caches, and captures the failure, when the entry '
            'cannot be revoked', () async {
          final deps = _setup();
          await deps.meetingCache.saveMeeting(_owner, aMeeting(), now);
          await deps.documentCache.save(
            _owner,
            ViewableDocument(
              document: aDocument(),
              location: aDocumentLocation(),
            ),
            now,
          );
          final failure = storageWriteFailed();
          final scripted = _Scripted(
            fetch: _answering(err(error)),
            revoke: err(failure),
          );

          expect(
            await loadWithCacheFallback(deps, _owner, scripted.source),
            equals(err(error)),
          );

          expect(
            deps.monitoring.errors,
            equals([
              ErrorRecord(
                event: MonitoringEvent.cacheRemoveFailed,
                error: failure,
                attributes: _logAttributes,
              ),
            ]),
          );
          expect(deps.meetingCache.isEmpty(), isTrue);
          expect(deps.documentCache.isEmpty(), isTrue);
        });

        test(
          'captures the failure of the purge too when even that fails',
          () async {
            final deps = _setup();
            deps.documentCache.purgeFailure = storageWriteFailed();
            final scripted = _Scripted(
              fetch: _answering(err(error)),
              revoke: err(storageWriteFailed()),
            );

            await loadWithCacheFallback(deps, _owner, scripted.source);

            expect(
              deps.monitoring.capturedEvents(),
              equals([
                MonitoringEvent.cacheRemoveFailed,
                MonitoringEvent.cachePurgeFailed,
              ]),
            );
          },
        );
      });
    }

    group('when the cache cannot be written', () {
      test('removes the entry, so that an older copy is not served afterwards '
          'as if it were current', () async {
        final deps = _setup();
        final scripted = _Scripted(
          fetch: _answering(ok(_remote)),
          save: err(storageWriteFailed()),
        );

        await loadWithCacheFallback(deps, _owner, scripted.source);

        expect(scripted.removals, equals(1));
        expect(scripted.revocations, equals(0));
      });

      test(
        'empties both caches when the entry cannot be removed either',
        () async {
          final deps = _setup();
          await deps.meetingCache.saveMeeting(_owner, aMeeting(), now);
          final scripted = _Scripted(
            fetch: _answering(ok(_remote)),
            save: err(storageWriteFailed()),
            remove: err(storageWriteFailed()),
          );

          final result = await loadWithCacheFallback(
            deps,
            _owner,
            scripted.source,
          );

          expect(isOk(result), isTrue);
          expect(deps.meetingCache.isEmpty(), isTrue);
          expect(
            deps.monitoring.capturedEvents(),
            equals([
              MonitoringEvent.cacheWriteFailed,
              MonitoringEvent.cacheRemoveFailed,
            ]),
          );
        },
      );
    });

    group('when the user is not the one the call was made for', () {
      test('writes nothing and answers sessionChanged, after a slow call that '
          'spanned a sign-in', () async {
        final deps = _setup();
        final scripted = _Scripted(
          fetch: () async {
            deps.auth.session = aSession(user: aUser(id: aUserId('user-2')));
            return ok(_remote);
          },
        );

        expect(
          await loadWithCacheFallback(deps, _owner, scripted.source),
          equals(err(sessionChanged())),
        );
        expect(scripted.saved, isEmpty);
      });

      test('empties both caches when a fetch that succeeded ends after a '
          'sign-in, since it may have kept a file', () async {
        final deps = _setup();
        final scripted = _Scripted(
          fetch: () async {
            deps.auth.session = aSession(user: aUser(id: aUserId('user-2')));
            return ok(_remote);
          },
        );

        await loadWithCacheFallback(deps, _owner, scripted.source);

        expect(deps.meetingCache.purgeCalls, equals(1));
        expect(deps.documentCache.purgeCalls, equals(1));
      });

      test('empties both caches when a fetch that succeeded ends after a '
          'sign-out', () async {
        final deps = _setup();
        final scripted = _Scripted(
          fetch: () async {
            deps.auth.session = null;
            return ok(_remote);
          },
        );

        expect(
          await loadWithCacheFallback(deps, _owner, scripted.source),
          equals(err(notAuthenticated())),
        );

        expect(scripted.saved, isEmpty);
        expect(deps.meetingCache.purgeCalls, equals(1));
        expect(deps.documentCache.purgeCalls, equals(1));
      });

      test('captures a purge that fails and still answers the refusal of the '
          'session', () async {
        final deps = _setup();
        deps.documentCache.purgeFailure = storageWriteFailed('disk full');
        final scripted = _Scripted(
          fetch: () async {
            deps.auth.session = null;
            return ok(_remote);
          },
        );

        expect(
          await loadWithCacheFallback(deps, _owner, scripted.source),
          equals(err(notAuthenticated())),
        );
        expect(
          deps.monitoring.capturedEvents(),
          equals([MonitoringEvent.cachePurgeFailed]),
        );
      });

      test('does not read the cache of the previous owner either, nor evict '
          'anything', () async {
        final deps = _setup();
        final scripted = _Scripted(
          fetch: () async {
            deps.auth.session = aSession(user: aUser(id: aUserId('user-2')));
            return err(networkUnavailable());
          },
          read: ok(_cached),
        );

        expect(
          await loadWithCacheFallback(deps, _owner, scripted.source),
          equals(err(sessionChanged())),
        );
        expect(
          scripted.reads + scripted.removals + scripted.revocations,
          equals(0),
        );
        // The remote call failed, so it kept nothing: the caches are left
        // alone.
        expect(
          deps.meetingCache.purgeCalls + deps.documentCache.purgeCalls,
          equals(0),
        );
      });

      test('answers appLocked when the app was locked meanwhile, and writes '
          'nothing', () async {
        final deps = _setup();
        final scripted = _Scripted(
          fetch: () async {
            deps.appLock.lock();
            return ok(_remote);
          },
        );

        expect(
          await loadWithCacheFallback(deps, _owner, scripted.source),
          equals(err(appLocked())),
        );
        expect(scripted.saved, isEmpty);
        // The user is the same and unlocks the app again: their cache is
        // not theirs to lose.
        expect(
          deps.meetingCache.purgeCalls + deps.documentCache.purgeCalls,
          equals(0),
        );
      });
    });

    group('when the remote source fails unexpectedly', () {
      test('returns the error as is and leaves the cache alone', () async {
        final error = unexpected('HTTP 500');
        final scripted = _Scripted(
          fetch: _answering(err(error)),
          read: ok(_cached),
        );

        expect(
          await loadWithCacheFallback(_setup(), _owner, scripted.source),
          equals(err(error)),
        );
        expect(scripted.reads, equals(0));
        expect(scripted.removals, equals(0));
      });
    });
  });
}
