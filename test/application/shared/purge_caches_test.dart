import 'package:boardroom/application/ports/document_cache.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/shared/cache_resource.dart';
import 'package:boardroom/application/shared/purge_caches.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:test/test.dart';

import '../../domain/support/builders.dart';
import '../support/create_fakes.dart';
import '../support/fake_monitoring.dart';

Future<void> _fill(Fakes fakes) async {
  await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
  await fakes.documentCache.save(
    aUserId(),
    ViewableDocument(document: aDocument(), location: aDocumentLocation()),
    now,
  );
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
}
