import 'dart:io';
import 'dart:typed_data';

import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/infrastructure/files/file_store.dart';
import 'package:boardroom/infrastructure/files/io_file_volume.dart';

import '../../application/support/contracts/document_cache_contract.dart';
import 'faulty_file_volume.dart';
import 'test_files.dart';

// Test support, not production code: the files of a device for the tests of the
// document caches. The contract suite of `DocumentCache` places its content at
// locations such as `file:///documents/document-1.pdf`, so the store says that
// is where its directory is, and the harness it offers (`files`) writes, looks
// at, loses and refuses to delete the files behind them.

/// Where the contract suite says the documents are.
const String contractDocumentsUri = 'file:///documents/';

/// What the content of a file is, in the tests: it is never read.
final Uint8List _content = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2d]);

/// The files of a device.
final class DocumentDevice {
  /// Creates the description of a device.
  const new({required this.store, required this.volume, required this.files});

  /// The store over the volume.
  final FileStore store;

  /// The volume, which can be made to fail.
  final FaultyFileVolume volume;

  /// What the contract suite of `DocumentCache` asks of the files.
  final DocumentFiles files;
}

/// The files of a device, in a directory of its own under [parent]. With
/// [realLocations] the files say they are where they are (`file:///tmp/...`)
/// instead of where the contract suite puts them, for a test that reads them
/// back from the disk. [timeoutMillis] is how long a call on the files may
/// take; it defaults to the one of the store.
///
/// [around] puts a volume of the test between the faulty one and the disk (a
/// volume that locks some files, say).
DocumentDevice aDocumentDevice(
  Directory parent, {
  int timeoutMillis = defaultFileTimeoutMillis,
  bool realLocations = false,
  FileVolume Function(FileVolume disk)? around,
}) {
  final directory = Directory('${freshDirectory(parent).path}/documents');
  final disk = IoFileVolume(
    directory,
    rootUri: realLocations ? null : contractDocumentsUri,
  );
  final volume = FaultyFileVolume(around == null ? disk : around(disk));
  final store = createFileStore(volume, timeoutMillis: timeoutMillis);

  String nameOf(String location) {
    final name = store.nameOf(location);
    if (name == null) {
      throw StateError('The location is no file of the store.');
    }
    return name;
  }

  return DocumentDevice(
    store: store,
    volume: volume,
    files: DocumentFiles(
      put: (location) async {
        final written = await store.write(nameOf(location), _content);
        if (written is Err) {
          throw StateError('The file could not be put there.');
        }
      },
      exists: (location) async {
        final stat = await store.stat(nameOf(location));
        return stat is Ok<StoredFile?, FileStoreFailure> && stat.value != null;
      },
      lose: (location) => volume.remove(nameOf(location)),
      breakDeletion: () => volume.fail(VolumeCall.remove, true),
      repairDeletion: () => volume.fail(VolumeCall.remove, false),
    ),
  );
}
