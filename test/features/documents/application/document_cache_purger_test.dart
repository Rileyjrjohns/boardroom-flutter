import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/documents/application/document_cache_purger.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/fake_document_cache.dart';

// The purger is how the documents feature takes part in the end of a session
// without auth importing its cache (see docs/architecture.md).

void main() {
  group('DocumentCachePurger', () {
    test('names the documents as what it empties, for the monitoring', () {
      expect(
        DocumentCachePurger(FakeDocumentCache()).resource,
        equals(CacheResource.document),
      );
    });

    test('empties the cache of the documents, for every owner', () async {
      final cache = FakeDocumentCache();
      final viewable = ViewableDocument(
        document: aDocument(),
        location: aDocumentLocation(),
      );
      await cache.save(aUserId(), viewable, now);
      await cache.save(aUserId('user-2'), viewable, now);

      final purged = await DocumentCachePurger(cache).purge();

      expect(purged, equals(ok<void>(null)));
      expect(cache.isEmpty(), isTrue);
    });

    test('gives the failure of a cache that cannot be emptied', () async {
      final cache = FakeDocumentCache()
        ..purgeFailure = storageWriteFailed('locked');

      final purged = await DocumentCachePurger(cache).purge();

      expect(purged, equals(err(storageWriteFailed('locked'))));
    });
  });
}
