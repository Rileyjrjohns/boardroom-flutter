import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/session_data_purger.dart';
import 'package:boardroom/features/auth/application/session/purge_caches.dart';
import 'package:test/test.dart';

import '../../../../support/fakes/fake_monitoring.dart';

// Dart only: `purgeCaches` runs the purgers that the composition registers, so
// auth does not know the features that keep data for a user.

/// A purger that notes when it ran, and fails when it is given a failure.
final class _Purger implements SessionDataPurger {
  new(this.resource, this._ran, {this.failure});

  @override
  final CacheResource resource;

  final List<CacheResource> _ran;
  final StorageWriteFailedError? failure;

  @override
  Future<Result<void, StorageWriteFailedError>> purge() {
    _ran.add(resource);
    final failure = this.failure;
    return Future.value(failure == null ? ok<void>(null) : err(failure));
  }
}

final class _Deps implements PurgeCachesDeps {
  new(this.sessionDataPurgers);

  @override
  final List<SessionDataPurger> sessionDataPurgers;

  @override
  final FakeMonitoring monitoring = FakeMonitoring();
}

void main() {
  group('purgeCaches over the registered purgers', () {
    test('runs every purger, in the order they are registered', () async {
      final ran = <CacheResource>[];
      final deps = _Deps([
        _Purger(CacheResource.document, ran),
        _Purger(CacheResource.meeting, ran),
      ]);

      await purgeCaches(deps);

      expect(ran, equals([CacheResource.document, CacheResource.meeting]));
      expect(deps.monitoring.errors, isEmpty);
    });

    test('does nothing when no purger is registered', () async {
      final deps = _Deps(const []);

      await purgeCaches(deps);

      expect(deps.monitoring.errors, isEmpty);
    });

    test('goes on after a purger that fails, and names each failure by the '
        'resource of its purger', () async {
      final ran = <CacheResource>[];
      final deps = _Deps([
        _Purger(CacheResource.meeting, ran, failure: storageWriteFailed('a')),
        _Purger(CacheResource.document, ran, failure: storageWriteFailed('b')),
        _Purger(CacheResource.meetingPage, ran),
      ]);

      await purgeCaches(deps);

      expect(
        ran,
        equals([
          CacheResource.meeting,
          CacheResource.document,
          CacheResource.meetingPage,
        ]),
      );
      expect(
        deps.monitoring.errors,
        equals([
          ErrorRecord(
            event: MonitoringEvent.cachePurgeFailed,
            error: storageWriteFailed('a'),
            attributes: {LogAttribute.resource: CacheResource.meeting.value},
          ),
          ErrorRecord(
            event: MonitoringEvent.cachePurgeFailed,
            error: storageWriteFailed('b'),
            attributes: {LogAttribute.resource: CacheResource.document.value},
          ),
        ]),
      );
    });
  });
}
