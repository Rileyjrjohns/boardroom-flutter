import 'package:boardroom/app/composition/session_data_purgers.dart';
import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:test/test.dart';

import '../../support/builders/builders.dart';
import '../../support/fakes/fake_document_cache.dart';
import '../../support/fakes/fake_meeting_cache.dart';

// The composition is where `auth` learns which features keep data for a user
// (see docs/architecture.md).

void main() {
  group('sessionDataPurgers', () {
    final meetingCache = FakeMeetingCache();
    final documentCache = FakeDocumentCache();

    test('is one purger for each feature that keeps data for a user: the '
        'meetings, then the documents', () {
      final purgers = sessionDataPurgers(
        meetingCache: meetingCache,
        documentCache: documentCache,
      );

      expect([
        for (final purger in purgers) purger.resource,
      ], equals([CacheResource.meeting, CacheResource.document]));
    });

    test('empties the cache of each feature', () async {
      final meetings = FakeMeetingCache();
      final documents = FakeDocumentCache();
      await meetings.saveMeeting(aUserId(), aMeeting(), now);
      await documents.save(
        aUserId(),
        ViewableDocument(document: aDocument(), location: aDocumentLocation()),
        now,
      );

      for (final purger in sessionDataPurgers(
        meetingCache: meetings,
        documentCache: documents,
      )) {
        expect(isOk(await purger.purge()), isTrue);
      }

      expect(meetings.isEmpty(), isTrue);
      expect(documents.isEmpty(), isTrue);
    });

    test('cannot be changed once built', () {
      final purgers = sessionDataPurgers(
        meetingCache: meetingCache,
        documentCache: documentCache,
      );

      expect(purgers.clear, throwsUnsupportedError);
    });
  });
}
