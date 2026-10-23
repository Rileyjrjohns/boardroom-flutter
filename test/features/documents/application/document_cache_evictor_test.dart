import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/documents/application/document_cache_evictor.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/fake_document_cache.dart';

// The evictor is the way the meetings feature reaches the document cache
// without importing it (see docs/architecture.md).

final UserId _alice = aUserId();
final UserId _bruno = aUserId('user-2');

void main() {
  group('DocumentCacheEvictor', () {
    test('drops the copy of a document that the owner kept, and only that '
        'one', () async {
      final cache = FakeDocumentCache();
      final viewable = ViewableDocument(
        document: aDocument(),
        location: aDocumentLocation(),
      );
      await cache.save(_alice, viewable, now);
      await cache.save(_bruno, viewable, now);

      final evicted = await DocumentCacheEvictor(cache)
          .evict(_alice, aDocumentId());

      expect(evicted, equals(ok<void>(null)));
      expect(await cache.read(_alice, aDocumentId()), equals(ok(null)));
      expect(isOk(await cache.read(_bruno, aDocumentId())), isTrue);
      expect(cache.isEmpty(), isFalse);
    });

    test('succeeds when the owner kept none', () async {
      final evicted = await DocumentCacheEvictor(FakeDocumentCache())
          .evict(_alice, aDocumentId());

      expect(evicted, equals(ok<void>(null)));
    });

    test('gives the failure of a cache that cannot be written', () async {
      final cache = FakeDocumentCache()..removeFailure = storageWriteFailed();

      expect(
        await DocumentCacheEvictor(cache).evict(_alice, aDocumentId()),
        equals(err(storageWriteFailed())),
      );
    });
  });
}
