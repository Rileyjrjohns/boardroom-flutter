import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/documents/application/document_cache_evictor.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/fake_document_cache.dart';

// Dart only: the evictor is the way the meetings feature reaches the document
// cache without importing it (see docs/architecture.md).

ViewableDocument _viewable() =>
    ViewableDocument(document: aDocument(), location: aDocumentLocation());

void main() {
  group('DocumentCacheEvictor', () {
    test('removes the copy of the document that the owner kept', () async {
      final cache = FakeDocumentCache();
      await cache.save(aUserId(), _viewable(), at(0));

      final evicted = await DocumentCacheEvictor(cache)
          .evict(aUserId(), aDocumentId());

      expect(evicted, equals(ok<void>(null)));
      expect(unwrap(await cache.read(aUserId(), aDocumentId())), isNull);
    });

    test('leaves the copy of another owner', () async {
      final cache = FakeDocumentCache();
      await cache.save(aUserId('user-2'), _viewable(), at(0));

      await DocumentCacheEvictor(cache).evict(aUserId(), aDocumentId());

      expect(
        unwrap(await cache.read(aUserId('user-2'), aDocumentId())),
        isNotNull,
      );
    });

    test('succeeds when there is no copy', () async {
      final evicted = await DocumentCacheEvictor(FakeDocumentCache())
          .evict(aUserId(), aDocumentId());

      expect(evicted, equals(ok<void>(null)));
    });

    test('returns the failure of the cache', () async {
      final cache = FakeDocumentCache()
        ..removeFailure = storageWriteFailed('disk');

      final evicted = await DocumentCacheEvictor(cache)
          .evict(aUserId(), aDocumentId());

      expect(evicted, equals(err(storageWriteFailed('disk'))));
    });
  });
}
