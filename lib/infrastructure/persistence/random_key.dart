import 'dart:math';
import 'dart:typed_data';

import 'package:boardroom/infrastructure/persistence/database_key.dart';

/// A source of secure random bytes: the number of bytes asked for, as a list of
/// that length. The device's one is `secureRandomBytes`, which draws from the
/// secure generator of the operating system, through the Dart runtime
/// (`Random.secure`), and throws instead of falling back on a weaker source. It
/// is a parameter and not a call so that the tests choose the bytes.
typedef RandomBytes = Future<Uint8List> Function(int byteCount);

/// The length of the key of the database: 256 bits.
const int keyBytes = 32;

const int _hexRadix = 16;
const int _hexDigitsPerByte = 2;
const int _byteRange = 256;

/// The key a source's bytes make: 64 lower-case hexadecimal digits
/// (`keyFormat`), which is the form a key has always been kept in. `null` when
/// the bytes cannot make a key: not exactly [keyBytes] of them, or all zero (a
/// generator that fails by answering zeros is broken, and a key of zeros would
/// look valid).
String? keyFromBytes(Uint8List bytes) {
  if (bytes.length != keyBytes || bytes.every((octet) => octet == 0)) {
    return null;
  }
  final key = bytes
      .map(
        (octet) =>
            octet.toRadixString(_hexRadix).padLeft(_hexDigitsPerByte, '0'),
      )
      .join();
  return keyFormat.hasMatch(key) ? key : null;
}

/// The secure random generator of the platform. It throws when the platform has
/// none.
Future<Uint8List> secureRandomBytes(int byteCount) async {
  final random = Random.secure();
  return Uint8List.fromList([
    for (var index = 0; index < byteCount; index++) random.nextInt(_byteRange),
  ]);
}
