import 'package:meta/meta.dart';

/// The key of the database: 256 bits as 64 lower case hexadecimal digits.
final RegExp keyFormat = RegExp(r'^[0-9a-f]{64}$');

/// The key and which file it opens (see [databaseFileName]). Kept in the
/// keychain as one item.
@immutable
final class KeyState {
  /// Creates the state of [generation] with [key].
  const new({required this.generation, required this.key});

  /// Which file the key opens.
  final int generation;

  /// The key, as [keyFormat] describes it.
  final String key;

  @override
  bool operator ==(Object other) =>
      other is KeyState && other.generation == generation && other.key == key;

  @override
  int get hashCode => Object.hash(generation, key);

  // The key is a secret: it is never printed.
  @override
  String toString() => 'KeyState($generation)';
}

/// The generation of the file the app starts with.
const int firstGeneration = 0;

const String _generationSeparator = ':';

/// `<generation>:<key>`, or a bare key, which is what an app that knew only one
/// file kept.
final RegExp _stateFormat = RegExp(r'^(?:([0-9]{1,6}):)?([0-9a-f]{64})$');

/// What is kept in the keychain for a state.
String formatKeyState(KeyState state) =>
    '${state.generation}$_generationSeparator${state.key}';

/// The state an item holds, or `null` for an item that is not one. The caller
/// tells the two apart: an item that is not there is a key that was lost, an
/// item that is there and does not read is a keychain that cannot be trusted.
KeyState? parseKeyState(String item) {
  final parts = _stateFormat.firstMatch(item);
  final key = parts?.group(2);
  if (key == null) {
    return null;
  }
  final generation = parts?.group(1);
  return KeyState(
    generation: generation == null ? firstGeneration : int.parse(generation),
    key: key,
  );
}

/// The name of the file of a generation of the database. The first one is
/// called [name], so that an app that knew only one file finds it. A file that
/// cannot be read is never deleted to make room for a new database: the next
/// generation is another file, and the one that could not be read stays where
/// it is (see `openProtectedDatabase`).
String databaseFileName(String name, int generation) =>
    generation == firstGeneration ? name : '$name.$generation';
