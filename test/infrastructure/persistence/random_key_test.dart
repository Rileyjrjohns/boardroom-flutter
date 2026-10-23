import 'dart:typed_data';

import 'package:boardroom/infrastructure/persistence/database_key.dart';
import 'package:boardroom/infrastructure/persistence/random_key.dart';
import 'package:test/test.dart';

// React Native tests the key through `openProtectedDatabase` only
// (`protectedDatabase.test.ts`, "where the key comes from" and "when no random
// key can be made"); these are the small functions on their own.

void main() {
  group('keyFromBytes', () {
    test('writes 32 bytes as 64 lower-case hexadecimal digits', () {
      final bytes = Uint8List.fromList([
        for (var index = 0; index < keyBytes; index++) 0xa0 + index,
      ]);

      final key = keyFromBytes(bytes);

      expect(
        key,
        equals(
          'a0a1a2a3a4a5a6a7a8a9aaabacadaeaf'
          'b0b1b2b3b4b5b6b7b8b9babbbcbdbebf',
        ),
      );
      expect(keyFormat.hasMatch(key!), isTrue);
    });

    test('writes a byte below 16 with a zero in front of it', () {
      final bytes = Uint8List(keyBytes)..[0] = 1;

      expect(keyFromBytes(bytes), equals('01${'0' * 62}'));
    });

    for (final count in [0, 1, keyBytes - 1, keyBytes + 1, 64]) {
      test('does not make a key of $count bytes', () {
        expect(keyFromBytes(Uint8List(count)..fillRange(0, count, 7)), isNull);
      });
    }

    test('does not make a key of zeros: a generator that fails '
        'by answering zeros is broken', () {
      expect(keyFromBytes(Uint8List(keyBytes)), isNull);
    });

    test('makes a key when one byte only is not zero', () {
      expect(
        keyFromBytes(Uint8List(keyBytes)..[keyBytes - 1] = 255),
        isNotNull,
      );
    });
  });

  group('secureRandomBytes', () {
    test('draws the number of bytes asked for', () async {
      expect(await secureRandomBytes(keyBytes), hasLength(keyBytes));
      expect(await secureRandomBytes(5), hasLength(5));
    });

    test('draws bytes that make a key, a different one each time', () async {
      final keys = {
        for (var draw = 0; draw < 5; draw++)
          keyFromBytes(await secureRandomBytes(keyBytes)),
      };

      expect(keys, hasLength(5));
      expect(keys, isNot(contains(null)));
    });
  });
}
