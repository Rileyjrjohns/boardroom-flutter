import 'dart:typed_data';

import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:test/test.dart';

import 'memory_file_volume.dart';

// The volume in memory is test support: these tests pin that it behaves like
// the volume of a device under the store, which is what lets other tests use
// it.

void main() {
  group('MemoryFileVolume', () {
    test('keeps a file whole or not at all under the store, and '
        'lists, looks at and deletes it', () async {
      final volume = MemoryFileVolume();
      final store = createFileStore(volume);

      expect(
        await store.write('a.pdf', Uint8List.fromList([1, 2, 3])),
        isA<Ok<void, FileStoreFailure>>(),
      );
      expect(await store.stat('a.pdf'), equals(ok(const StoredFile(size: 3))));
      expect(await store.list(), equals(ok(['a.pdf'])));
      expect(store.uriOf('a.pdf'), equals('${memoryRootUri}a.pdf'));
      expect(await store.deleteAll(), isA<Ok<void, FileStoreFailure>>());
      expect(volume.files, isEmpty);
    });

    test('copies the bytes it is given, so that a later change of '
        'them changes nothing', () async {
      final volume = MemoryFileVolume();
      final bytes = Uint8List.fromList([1]);

      await volume.write('a.pdf', bytes);
      bytes[0] = 9;

      expect(volume.files['a.pdf'], equals([1]));
    });

    test('cannot move a file that is not there', () async {
      await expectLater(
        MemoryFileVolume().move('a', 'b'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
