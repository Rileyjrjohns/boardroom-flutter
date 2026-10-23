import 'dart:io';
import 'dart:typed_data';

import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/core/infrastructure/files/io_file_volume.dart';
import 'package:test/test.dart';

import '../../../support/infrastructure/faulty_file_volume.dart';
import '../../../support/infrastructure/test_files.dart';

// The store is tested over the file system of the machine, which is the real
// thing, and over a volume that fails when it is told to. Nothing here depends
// on a device: the volume of a device only renames the calls (see
// io_file_volume_test.dart).

Uint8List _bytesOf(List<int> values) => Uint8List.fromList(values);

String _join(Directory directory, String name) => '${directory.path}/$name';

List<String> _namesIn(Directory directory) => directory.existsSync()
    ? directory
          .listSync()
          .map(
            (entry) => entry.uri.pathSegments.where((s) => s.isNotEmpty).last,
          )
          .toList()
    : [];

const String _invalidName = 'invalid file name';

void main() {
  final parent = temporaryDirectory();

  // The time limit of a call is short only in the test that makes the volume
  // hang. The writes of the others go to the disk of the machine and are
  // flushed to it, which a loaded machine can take more than 50 milliseconds
  // to do: a call that is cut off for being slow would fail a test that is not
  // about time.
  ({Directory directory, FaultyFileVolume faulty, FileStore store}) aStore({
    int timeoutMillis = defaultFileTimeoutMillis,
  }) {
    final directory = Directory('${freshDirectory(parent).path}/documents');
    final faulty = FaultyFileVolume(IoFileVolume(directory));
    return (
      directory: directory,
      faulty: faulty,
      store: createFileStore(faulty, timeoutMillis: timeoutMillis),
    );
  }

  group('the names of the files', () {
    for (final name in ['a.pdf', 'document-1.pdf', 'A_b-c.1.pdf', '0']) {
      test('accepts $name', () {
        expect(isValidFileName(name), isTrue);
      });
    }

    for (final (what, name) in [
      ('nothing', ''),
      ('a path', 'a/b.pdf'),
      ('a path upwards', '../a.pdf'),
      ('a backslash', r'a\b.pdf'),
      ('a name that starts with a dot', '.hidden'),
      ('a space', 'a b.pdf'),
      ('a percent sign', 'a%2Fb'),
      ('an accent', 'café.pdf'),
      ('a partial file', 'a.pdf$partialSuffix'),
      ('a name that is too long', 'a' * 129),
    ]) {
      test('refuses $what', () {
        expect(isValidFileName(name), isFalse);
      });
    }
  });

  group('FileStore', () {
    group('writing and reading back', () {
      test(
        'writes the bytes, and says that the file is there and how big it is',
        () async {
          final (:store, :directory, faulty: _) = aStore();

          expect(
            await store.write('a.pdf', _bytesOf([1, 2, 3])),
            equals(ok<void>(null)),
          );

          expect(
            await store.stat('a.pdf'),
            equals(ok(const StoredFile(size: 3))),
          );
          expect(
            File(_join(directory, 'a.pdf')).readAsBytesSync(),
            equals([1, 2, 3]),
          );
        },
      );

      test(
        'makes its directory when there is none, and again if it is taken away',
        () async {
          final (:store, :directory, faulty: _) = aStore();
          await store.write('a.pdf', _bytesOf([1]));
          directory.deleteSync(recursive: true);

          expect(
            await store.write('b.pdf', _bytesOf([2])),
            isA<Ok<void, FileStoreFailure>>(),
          );

          expect(await store.list(), equals(ok(['b.pdf'])));
        },
      );

      test(
        'says nothing is there for a file it never had, without failing',
        () async {
          final (:store, directory: _, faulty: _) = aStore();

          expect(
            await store.stat('missing.pdf'),
            equals(ok<StoredFile?>(null)),
          );
        },
      );

      test('replaces a file written again under the same name', () async {
        final (:store, directory: _, faulty: _) = aStore();
        await store.write('a.pdf', _bytesOf([1, 2, 3]));

        await store.write('a.pdf', _bytesOf([9]));

        expect(
          await store.stat('a.pdf'),
          equals(ok(const StoredFile(size: 1))),
        );
      });

      test('writes an empty file', () async {
        final (:store, directory: _, faulty: _) = aStore();

        await store.write('empty.pdf', Uint8List(0));

        expect(
          await store.stat('empty.pdf'),
          equals(ok(const StoredFile(size: 0))),
        );
      });
    });

    group('a write is whole or nothing', () {
      test('leaves no partial file behind once it is done', () async {
        final (:store, :directory, faulty: _) = aStore();

        await store.write('a.pdf', _bytesOf([1, 2, 3]));

        expect(_namesIn(directory), equals(['a.pdf']));
      });

      test('never shows half a file under the name: the bytes are in '
          'a file of their own until the move', () async {
        final (:store, :faulty, :directory) = aStore();
        await store.write('a.pdf', _bytesOf([1, 2, 3]));
        faulty.fail(VolumeCall.move, true);

        final failed = await store.write('a.pdf', _bytesOf([9, 9]));

        expect(failed, isA<Err<void, FileStoreFailure>>());
        // The previous file is as it was, and the partial one is gone.
        expect(
          File(_join(directory, 'a.pdf')).readAsBytesSync(),
          equals([1, 2, 3]),
        );
        expect(_namesIn(directory), equals(['a.pdf']));
      });

      test('leaves nothing when the bytes cannot be written', () async {
        final (:store, :faulty, :directory) = aStore();
        faulty.fail(VolumeCall.write, true);

        final failed = await store.write('a.pdf', _bytesOf([1]));

        expect(failed, isA<Err<void, FileStoreFailure>>());
        expect(_namesIn(directory), isEmpty);
      });

      test('uses a partial file name no other write uses, so that two '
          'writes at once do not meet', () async {
        final (:store, directory: _, faulty: _) = aStore();

        final results = await Future.wait([
          for (final byte in [1, 2, 3, 4, 5])
            store.write('a.pdf', _bytesOf([byte, byte])),
        ]);

        expect(results.every((result) => result is Ok), isTrue);
        expect(await store.list(), equals(ok(['a.pdf'])));
      });
    });

    group('deleting', () {
      test('deletes a file, and succeeds for one that is not there', () async {
        final (:store, directory: _, faulty: _) = aStore();
        await store.write('a.pdf', _bytesOf([1]));

        expect(await store.delete('a.pdf'), isA<Ok<void, FileStoreFailure>>());
        expect(await store.delete('a.pdf'), isA<Ok<void, FileStoreFailure>>());

        expect(await store.stat('a.pdf'), equals(ok<StoredFile?>(null)));
      });

      test(
        'lists everything, files that were being written included',
        () async {
          final (:store, directory: _, faulty: _) = aStore();
          await store.write('a.pdf', _bytesOf([1]));
          await store.write('b.pdf', _bytesOf([2]));

          final listed = await store.list();

          expect(
            listed,
            isA<Ok<List<String>, FileStoreFailure>>().having(
              (result) => List.of(result.value)..sort(),
              'names',
              equals(['a.pdf', 'b.pdf']),
            ),
          );
        },
      );

      test('deletes everything, and succeeds when there is nothing', () async {
        final (:store, directory: _, faulty: _) = aStore();
        expect(await store.deleteAll(), isA<Ok<void, FileStoreFailure>>());
        await store.write('a.pdf', _bytesOf([1]));
        await store.write('b.pdf', _bytesOf([2]));

        expect(await store.deleteAll(), isA<Ok<void, FileStoreFailure>>());

        expect(await store.list(), equals(ok(<String>[])));
      });

      test(
        'goes on after a file it cannot delete, takes the others, and fails',
        () async {
          final (:store, :faulty, directory: _) = aStore();
          await store.write('a.pdf', _bytesOf([1]));
          await store.write('b.pdf', _bytesOf([2]));
          await store.write('c.pdf', _bytesOf([3]));
          faulty.fail(VolumeCall.remove, true);

          final failed = await store.deleteAll();

          expect(
            failed,
            equals(err(const FileStoreFailure(cause: 'os error 5'))),
          );
          // Every file was tried: three attempts, not one.
          expect(faulty.calls[VolumeCall.remove], equals(3));
        },
      );
    });

    group('locations', () {
      test('makes the location of a file from the root of the volume, '
          'and reads the name back', () {
        final (:store, :directory, faulty: _) = aStore();

        expect(store.uriOf('a.pdf'), equals('${directory.uri}a.pdf'));
        expect(store.nameOf(store.uriOf('a.pdf')), equals('a.pdf'));
      });

      for (final (what, template) in [
        ('another directory', 'file:///elsewhere/a.pdf'),
        ('a file in a directory below', 'DIRECTORY/sub/a.pdf'),
        ('a path upwards', 'DIRECTORY/../a.pdf'),
        ('nothing after the root', 'DIRECTORY/'),
        ('a partial file', 'DIRECTORY/a.pdf$partialSuffix'),
        ('a memory location', 'memory://documents/1/user-1/document-1'),
      ]) {
        test('does not read a name from $what', () {
          final (:store, :directory, faulty: _) = aStore();
          final root = directory.uri.toString().replaceFirst(RegExp(r'/$'), '');

          expect(
            store.nameOf(template.replaceFirst('DIRECTORY', root)),
            isNull,
          );
        });
      }

      test('can be told to use the locations of its callers instead '
          'of the directory', () async {
        final directory = Directory('${freshDirectory(parent).path}/documents');
        final store = createFileStore(
          IoFileVolume(directory, rootUri: 'file:///documents/'),
        );
        await store.write('document-1.pdf', _bytesOf([1]));

        expect(
          store.uriOf('document-1.pdf'),
          equals('file:///documents/document-1.pdf'),
        );
        expect(
          store.nameOf('file:///documents/document-1.pdf'),
          equals('document-1.pdf'),
        );
        expect(File(_join(directory, 'document-1.pdf')).existsSync(), isTrue);
      });
    });

    group('failures', () {
      for (final name in ['a/b.pdf', '..', '', '.hidden', 'café.pdf']) {
        test('refuses the name ${_quoted(name)} in every call, and '
            'never reaches the volume', () async {
          final (:store, :faulty, directory: _) = aStore();
          final failure = err(const FileStoreFailure(cause: _invalidName));

          expect(await store.write(name, _bytesOf([1])), equals(failure));
          expect(await store.stat(name), equals(failure));
          expect(await store.delete(name), equals(failure));

          expect(
            faulty.calls,
            equals({for (final call in VolumeCall.values) call: 0}),
          );
        });
      }

      test('does not write nor look at a file that was being written, '
          'but deletes it', () async {
        final (:store, :faulty, :directory) = aStore();
        const partial = 'a.pdf.x1$partialSuffix';
        await store.write('a.pdf', _bytesOf([1]));
        await faulty.write(partial, _bytesOf([2]));
        final failure = err(const FileStoreFailure(cause: _invalidName));

        expect(await store.write(partial, _bytesOf([1])), equals(failure));
        expect(await store.stat(partial), equals(failure));
        expect(await store.delete(partial), isA<Ok<void, FileStoreFailure>>());

        expect(_namesIn(directory), equals(['a.pdf']));
      });

      test('turns a call that fails into a failure whose cause is the '
          'code, never a path or a message', () async {
        final (:store, :faulty, directory: _) = aStore();
        faulty
          ..fail(VolumeCall.size, true)
          ..fail(VolumeCall.list, true)
          ..fail(VolumeCall.remove, true)
          ..fail(VolumeCall.ensureRoot, true);

        final results = [
          await store.stat('a.pdf'),
          await store.list(),
          await store.delete('a.pdf'),
          await store.write('a.pdf', _bytesOf([1])),
          await store.deleteAll(),
        ];

        expect(
          results,
          equals(
            results.map(
              (_) => err(const FileStoreFailure(cause: 'os error 5')),
            ),
          ),
        );
      });

      test(
        'gives a failure without a code the cause "unknown failure"',
        () async {
          final throwing = createFileStore(_ThrowingVolume());

          expect(
            await throwing.write('a.pdf', _bytesOf([1])),
            equals(err(const FileStoreFailure(cause: 'unknown failure'))),
          );
        },
      );

      test(
        'settles in bounded time when the file system never answers',
        () async {
          final (:store, :faulty, directory: _) = aStore(timeoutMillis: 50);
          faulty
            ..hang(VolumeCall.size, true)
            ..hang(VolumeCall.write, true);

          final stat = await store.stat('a.pdf');
          final write = await store.write('a.pdf', _bytesOf([1]));

          expect(stat, equals(err(const FileStoreFailure(cause: 'timeout'))));
          expect(write, equals(err(const FileStoreFailure(cause: 'timeout'))));
        },
      );
    });
  });
}

String _quoted(String name) => name == '' ? '""' : '"$name"';

final class _ThrowingVolume implements FileVolume {
  @override
  String get rootUri => 'file:///x/';

  @override
  Future<void> ensureRoot() => Future.error(StateError('/secret/path'));

  @override
  Future<void> write(String name, Uint8List bytes) =>
      Future.error(StateError('/secret/path'));

  @override
  Future<void> move(String from, String to) =>
      Future.error(StateError('/secret/path'));

  @override
  Future<int?> size(String name) => Future.error(StateError('/secret/path'));

  @override
  Future<void> remove(String name) => Future.error(StateError('/secret/path'));

  @override
  Future<List<String>> list() => Future.error(StateError('/secret/path'));
}
