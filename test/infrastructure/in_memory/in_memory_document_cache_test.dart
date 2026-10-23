import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_document_cache.dart';

import '../../application/support/contracts/document_cache_contract.dart';
import '../support/document_device.dart';
import '../support/test_files.dart';

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
