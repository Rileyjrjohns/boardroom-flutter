import 'dart:typed_data';

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:boardroom/features/documents/infrastructure/document_content.dart';
import 'package:boardroom/features/documents/infrastructure/store_document_content.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/fake_monitoring.dart';
import '../../../support/infrastructure/faulty_file_volume.dart';
import '../../../support/infrastructure/memory_file_volume.dart';

// The content of the documents: the name of the file of a download, and what
// the document caches ask of the files by location. React Native has no test
// file of its own for these modules (the repositories' tests cover them); these
// tests are listed in docs/parity/infrastructure.md.

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

({
  MemoryFileVolume memory,
  FaultyFileVolume volume,
  FileStore files,
  FakeMonitoring monitoring,
})
_aDevice() {
  final memory = MemoryFileVolume();
  final volume = FaultyFileVolume(memory);
  return (
    memory: memory,
    volume: volume,
    files: createFileStore(volume, timeoutMillis: 50),
    monitoring: FakeMonitoring(),
  );
}

DownloadedDocument _download({
  String version = '"v1"',
  List<int> bytes = const [1, 2, 3],
}) => DownloadedDocument(
  userId: aUserId(),
  documentId: aDocumentId(),
  version: version,
  bytes: _bytes(bytes),
);

void main() {
  group('documentFileName', () {
    test('is 64 hexadecimal digits and the extension of a PDF', () {
      expect(
        documentFileName(aUserId(), aDocumentId(), 'v1'),
        matches(RegExp(r'^[0-9a-f]{64}\.pdf$')),
      );
    });

    test('is the same for the same user, document and version', () {
      expect(
        documentFileName(aUserId(), aDocumentId(), 'v1'),
        equals(documentFileName(aUserId(), aDocumentId(), 'v1')),
      );
    });

    test(
      'is another for another user, another document or another version',
      () {
        final base = documentFileName(aUserId(), aDocumentId(), 'v1');

        expect(
          documentFileName(aUserId('user-2'), aDocumentId(), 'v1'),
          isNot(equals(base)),
        );
        expect(
          documentFileName(aUserId(), aDocumentId('document-2'), 'v1'),
          isNot(equals(base)),
        );
        expect(
          documentFileName(aUserId(), aDocumentId(), 'v2'),
          isNot(equals(base)),
        );
      },
    );

    test('never joins the parts in one text: two splits of the same '
        'characters are two names', () {
      expect(
        documentFileName(aUserId('a|b'), aDocumentId('c'), 'v'),
        isNot(equals(documentFileName(aUserId('a'), aDocumentId('b|c'), 'v'))),
      );
    });

    test('is a valid name for the store, whatever the identifiers contain', () {
      final name = documentFileName(
        aUserId('../é "quoted"\n'),
        aDocumentId(r'/\'),
        '%00',
      );

      expect(isValidFileName(name), isTrue);
    });
  });

  group('storeDocumentContent', () {
    test('keeps the download in the file of its user, document and '
        'version, and says where it is', () async {
      final (:memory, volume: _, :files, :monitoring) = _aDevice();
      final download = _download();

      final stored = await storeDocumentContent(
        StoreDocumentContentDeps(files: files, monitoring: monitoring),
        download,
      );

      final name = documentFileName(aUserId(), aDocumentId(), '"v1"');
      expect(
        stored,
        equals(ok(unwrap(parseDocumentLocation('${memory.rootUri}$name')))),
      );
      expect(memory.files[name], equals([1, 2, 3]));
    });

    test(
      'replaces the file with what the same download has just fetched',
      () async {
        final (:memory, volume: _, :files, :monitoring) = _aDevice();
        final deps = StoreDocumentContentDeps(
          files: files,
          monitoring: monitoring,
        );

        await storeDocumentContent(deps, _download());
        await storeDocumentContent(deps, _download(bytes: [9]));

        expect(
          memory.files.values.map((bytes) => bytes.toList()),
          equals([
            [9],
          ]),
        );
      },
    );

    test('keeps two versions in two files', () async {
      final (:memory, volume: _, :files, :monitoring) = _aDevice();
      final deps = StoreDocumentContentDeps(
        files: files,
        monitoring: monitoring,
      );

      await storeDocumentContent(deps, _download());
      await storeDocumentContent(deps, _download(version: '"v2"'));

      expect(memory.files, hasLength(2));
    });

    test('is unexpected, with a cause that is a kind of failure, '
        'when the file cannot be written; and tells the monitoring '
        'what the file system said, and nothing else', () async {
      final (:memory, :volume, :files, :monitoring) = _aDevice();
      volume.fail(VolumeCall.write, true);

      final stored = await storeDocumentContent(
        StoreDocumentContentDeps(files: files, monitoring: monitoring),
        _download(),
      );

      expect(stored, equals(err(unexpected('content not stored'))));
      expect(memory.files, isEmpty);
      expect(monitoring.errors, hasLength(1));
      final record = monitoring.errors.single;
      expect(record.event, equals(MonitoringEvent.documentContentNotStored));
      expect(record.error, equals(storageWriteFailed('os error 5')));
      expect(
        record.attributes,
        equals({
          LogAttribute.resource: 'documentContent',
          LogAttribute.documentId: aDocumentId(),
        }),
      );
      expect('${monitoring.errors}', isNot(contains('/secret/path')));
    });
  });

  group('contentExists and deleteContent', () {
    test(
      'tell whether the content a location points at is there, and delete it',
      () async {
        final (memory: _, volume: _, :files, monitoring: _) = _aDevice();
        await files.write('a.pdf', _bytes([1]));
        final location = unwrap(parseDocumentLocation(files.uriOf('a.pdf')));

        expect(await contentExists(files, location), equals(ok(true)));
        expect(
          await deleteContent(files, location),
          isA<Ok<void, FileStoreFailure>>(),
        );
        expect(await contentExists(files, location), equals(ok(false)));
      },
    );

    test('find nothing, and delete nothing, at a location that is '
        'no file of the store', () async {
      final (memory: _, :volume, :files, monitoring: _) = _aDevice();
      final elsewhere = unwrap(
        parseDocumentLocation('file:///elsewhere/a.pdf'),
      );

      expect(await contentExists(files, elsewhere), equals(ok(false)));
      expect(
        await deleteContent(files, elsewhere),
        isA<Ok<void, FileStoreFailure>>(),
      );
      expect(volume.calls.values.every((count) => count == 0), isTrue);
    });

    test('report a file system that fails', () async {
      final (memory: _, :volume, :files, monitoring: _) = _aDevice();
      final location = unwrap(parseDocumentLocation(files.uriOf('a.pdf')));
      volume
        ..fail(VolumeCall.size, true)
        ..fail(VolumeCall.remove, true);

      expect(
        await contentExists(files, location),
        equals(err(const FileStoreFailure(cause: 'os error 5'))),
      );
      expect(
        await deleteContent(files, location),
        equals(err(const FileStoreFailure(cause: 'os error 5'))),
      );
    });
  });
}
