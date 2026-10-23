import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/features/documents/infrastructure/in_memory_document_cache.dart';

import '../../../support/contracts/document_cache_contract.dart';
import '../../../support/infrastructure/document_device.dart';
import '../../../support/infrastructure/test_files.dart';

void main() {
  final parent = temporaryDirectory();

  // The entries are in memory, the content is in files of a directory of the
  // machine, behind a store that can be made to fail to delete.
  describeDocumentCacheContract(
    'InMemoryDocumentCache',
    () {
      final device = aDocumentDevice(parent);
      final cache = InMemoryDocumentCache(device.store);
      return DocumentCacheHarness(
        cache: cache,
        breakWrites: () => cache.failWritesWith(storageWriteFailed()),
        repairWrites: () => cache.failWritesWith(null),
        files: device.files,
      );
    },
    const DocumentCacheContractOptions(
      failsStatements: false,
      survivesReopen: false,
      keepsFiles: true,
    ),
  );
}
