import 'dart:io';
import 'dart:typed_data';

import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/files/create_device_file_store.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/core/infrastructure/files/io_file_volume.dart';
import 'package:test/test.dart';

import '../../../support/infrastructure/faulty_file_volume.dart';
import '../../../support/infrastructure/test_files.dart';

// The volume of a device only renames the calls of the file system: it decides
// nothing (the whole-or-nothing write, the names, the time limits and the
// failures that are values are in `createFileStore`). What is left to check is
// the conversation with the file system, and that the store works over it.

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  final parent = temporaryDirectory();

  IoFileVolume aVolume() =>
      IoFileVolume(Directory('${freshDirectory(parent).path}/documents'));

  group('IoFileVolume', () {
    group('where it is', () {
      test('is the location of its directory, with a slash at the end', () {
        final directory = Directory('${freshDirectory(parent).path}/documents');

        expect(IoFileVolume(directory).rootUri, endsWith('/documents/'));
        expect(IoFileVolume(directory).rootUri, startsWith('file:///'));
      });

      test('says the location it is told to say', () {
        final directory = Directory('${freshDirectory(parent).path}/documents');

        expect(
          IoFileVolume(directory, rootUri: 'file:///documents/').rootUri,
          equals('file:///documents/'),
        );
      });
    });

    group('the calls it makes', () {
      test('makes its directory, and the ones above it, and makes it '
          'again without failing', () async {
        final directory = Directory(
          '${freshDirectory(parent).path}/a/b/documents',
        );
        final volume = IoFileVolume(directory);

        await volume.ensureRoot();
        await volume.ensureRoot();

        expect(directory.existsSync(), isTrue);
      });

      test('writes a file by creating it, over what is there, and '
          'writing the bytes', () async {
        final volume = aVolume();
        await volume.ensureRoot();

        await volume.write('a.pdf', _bytes([1, 2, 3]));
        await volume.write('a.pdf', _bytes([9]));

        expect(await volume.size('a.pdf'), equals(1));
        expect(await volume.list(), equals(['a.pdf']));
      });

      test('moves a file onto another, over it', () async {
        final volume = aVolume();
        await volume.ensureRoot();
        await volume.write('a.pdf', _bytes([1]));
        await volume.write('b.pdf.part', _bytes([2]));

        await volume.move('b.pdf.part', 'a.pdf');

        expect(await volume.list(), equals(['a.pdf']));
        expect(await volume.size('a.pdf'), equals(1));
      });

      test(
        'says the size of a file, and nothing for a file that is not there',
        () async {
          final volume = aVolume();
          await volume.ensureRoot();
          await volume.write('a.pdf', _bytes([1, 2, 3]));

          expect(await volume.size('a.pdf'), equals(3));
          expect(await volume.size('missing.pdf'), isNull);
        },
      );

      test(
        'deletes a file, and a file that is not there is not an error',
        () async {
          final volume = aVolume();
          await volume.ensureRoot();
          await volume.write('a.pdf', _bytes([1]));

          await volume.remove('a.pdf');
          await volume.remove('a.pdf');

          expect(await volume.list(), isEmpty);
        },
      );

      test(
        'lists the names of the files, and leaves the directories out',
        () async {
          final directory = Directory(
            '${freshDirectory(parent).path}/documents',
          );
          final volume = IoFileVolume(directory);
          await volume.ensureRoot();
          await volume.write('a.pdf', _bytes([1]));
          await volume.write('b.pdf', _bytes([1]));
          Directory('${directory.path}/sub').createSync();

          expect((await volume.list())..sort(), equals(['a.pdf', 'b.pdf']));
        },
      );

      test('lets what the module says go, as a rejection and '
          'never as an exception', () async {
        final volume = aVolume();

        // The directory was never made: the file system refuses to list it and
        // to create a file in it.
        await expectLater(volume.list(), throwsA(isA<FileSystemException>()));
        await expectLater(
          volume.write('a.pdf', _bytes([1])),
          throwsA(isA<FileSystemException>()),
        );
        await expectLater(
          volume.move('a.pdf', 'b.pdf'),
          throwsA(isA<FileSystemException>()),
        );
      });
    });

    group('under the store', () {
      test(
        'keeps a file whole or not at all, and lists, looks at and deletes it',
        () async {
          final volume = aVolume();
          final store = createFileStore(volume);

          expect(
            await store.write('a.pdf', _bytes([1, 2, 3])),
            isA<Ok<void, FileStoreFailure>>(),
          );
          expect(
            await store.stat('a.pdf'),
            equals(ok(const StoredFile(size: 3))),
          );
          expect(await store.list(), equals(ok(['a.pdf'])));
          expect(store.nameOf(store.uriOf('a.pdf')), equals('a.pdf'));
          expect(store.uriOf('a.pdf'), equals('${volume.rootUri}a.pdf'));
          expect(await store.deleteAll(), isA<Ok<void, FileStoreFailure>>());
          expect(await store.list(), equals(ok(<String>[])));
        },
      );

      test('leaves no partial file when the move fails', () async {
        final faulty = FaultyFileVolume(aVolume());
        final store = createFileStore(faulty);
        await store.write('a.pdf', _bytes([1]));
        faulty.fail(VolumeCall.move, true);

        final failed = await store.write('a.pdf', _bytes([9, 9]));

        expect(
          failed,
          equals(err(const FileStoreFailure(cause: 'os error 5'))),
        );
        expect(await store.list(), equals(ok(['a.pdf'])));
      });
    });
  });

  group('createDeviceFileStore', () {
    Future<Directory> locate(DeviceStorage storage) async =>
        Directory('${parent.path}/${storage.name}')
          ..createSync(recursive: true);

    test('keeps the documents in the caches directory on iOS', () async {
      final store = await createDeviceFileStore(isIos: true, locate: locate);

      expect(
        store.uriOf('a.pdf'),
        endsWith('/cache/$documentDirectoryName/a.pdf'),
      );
    });

    test(
      'keeps the documents in the private storage of the app on Android',
      () async {
        final store = await createDeviceFileStore(isIos: false, locate: locate);

        expect(
          store.uriOf('a.pdf'),
          endsWith('/private/$documentDirectoryName/a.pdf'),
        );
      },
    );

    test('chooses the storage by the platform', () {
      expect(deviceStorageOf(isIos: true), equals(DeviceStorage.cache));
      expect(deviceStorageOf(isIos: false), equals(DeviceStorage.private));
    });
  });
}
