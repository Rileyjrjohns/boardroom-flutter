import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/session_data_purger.dart';
import 'package:boardroom/features/auth/application/session/purge_caches.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/fakes/create_fakes.dart';
import '../../../../support/fakes/fake_monitoring.dart';

Future<void> _fill(Fakes fakes) async {
  await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
  await fakes.documentCache.save(
    aUserId(),
    ViewableDocument(document: aDocument(), location: aDocumentLocation()),
    now,
  );
}

/// A purger of a feature that nothing in `auth` knows: it records the order it
/// was called in.
final class _Purger implements SessionDataPurger {
  new(this.resource, this._calls, [this._outcome]);

  @override
  final CacheResource resource;

  final List<CacheResource> _calls;
  final StorageWriteFailedError? _outcome;

  @override
  Future<Result<void, StorageWriteFailedError>> purge() {
    _calls.add(resource);
    final failure = _outcome;
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
  group('purgeCaches', () {
    test('empties the meeting cache and the document cache', () async {
      final fakes = createFakes();
      await _fill(fakes);

      await purgeCaches(fakes);

      expect(fakes.meetingCache.isEmpty(), isTrue);
      expect(fakes.documentCache.isEmpty(), isTrue);
      expect(fakes.monitoring.errors, isEmpty);
    });

    test('still empties the document cache when the meeting cache cannot be '
        'emptied, and captures it', () async {
      final fakes = createFakes();
      await _fill(fakes);
      fakes.meetingCache.purgeFailure = storageWriteFailed();

      await purgeCaches(fakes);

      expect(fakes.documentCache.isEmpty(), isTrue);
      expect(
        fakes.monitoring.errors,
        equals([
          ErrorRecord(
            event: MonitoringEvent.cachePurgeFailed,
            error: storageWriteFailed(),
            attributes: {LogAttribute.resource: CacheResource.meeting.value},
          ),
        ]),
      );
    });

    test('still empties the meeting cache when the document cache cannot be '
        'emptied, and captures it', () async {
      final fakes = createFakes();
      await _fill(fakes);
      fakes.documentCache.purgeFailure = storageWriteFailed('content locked');

      await purgeCaches(fakes);

      expect(fakes.meetingCache.isEmpty(), isTrue);
      expect(
        fakes.monitoring.errors,
        equals([
          ErrorRecord(
            event: MonitoringEvent.cachePurgeFailed,
            error: storageWriteFailed('content locked'),
            attributes: {LogAttribute.resource: CacheResource.document.value},
          ),
        ]),
      );
    });
  });

  group('purgeCaches, over the purgers it is given', () {
    test('runs them in the order of the list, which the composition '
        'decides', () async {
      final calls = <CacheResource>[];
      final deps = _Deps([
        _Purger(CacheResource.document, calls),
        _Purger(CacheResource.meeting, calls),
      ]);

      await purgeCaches(deps);

      expect(calls, equals([CacheResource.document, CacheResource.meeting]));
      expect(deps.monitoring.errors, isEmpty);
    });

    test('attempts every purger, whatever the one before it did, and names '
        'the resource that failed', () async {
      final calls = <CacheResource>[];
      final deps = _Deps([
        _Purger(CacheResource.meeting, calls, storageWriteFailed('first')),
        _Purger(CacheResource.document, calls, storageWriteFailed('second')),
      ]);

      await purgeCaches(deps);

      expect(calls, equals([CacheResource.meeting, CacheResource.document]));
      expect(
        deps.monitoring.errors,
        equals([
          ErrorRecord(
            event: MonitoringEvent.cachePurgeFailed,
            error: storageWriteFailed('first'),
            attributes: {LogAttribute.resource: CacheResource.meeting.value},
          ),
          ErrorRecord(
            event: MonitoringEvent.cachePurgeFailed,
            error: storageWriteFailed('second'),
            attributes: {LogAttribute.resource: CacheResource.document.value},
          ),
        ]),
      );
    });

    test('does nothing, and fails nothing, when no feature keeps data for a '
        'user', () async {
      final deps = _Deps(const []);

      await purgeCaches(deps);

      expect(deps.monitoring.errors, isEmpty);
    });
  });
}
