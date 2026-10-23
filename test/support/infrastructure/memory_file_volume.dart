import 'dart:typed_data';

import 'package:boardroom/core/infrastructure/files/file_store.dart';

// Test support, not production code: a file system in memory, for the tests
// that do not need a disk. Like the volume of the device, it keeps no logic of
// its own: the store is what decides.

/// The default location of the files of a [MemoryFileVolume].
const String memoryRootUri = 'file:///memory/documents/';

/// A directory held in memory.
final class MemoryFileVolume implements FileVolume {
  /// Creates an empty volume whose files are said to be at [rootUri].
  new({this.rootUri = memoryRootUri});

  @override
  final String rootUri;

  final Map<String, Uint8List> _files = {};

  /// What the files hold, by name, to compare with what was written.
  Map<String, Uint8List> get files => Map.unmodifiable(_files);

  @override
  Future<void> ensureRoot() async {}

  @override
  Future<void> write(String name, Uint8List bytes) async {
    _files[name] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> move(String from, String to) async {
    final bytes = _files.remove(from);
    if (bytes == null) {
      throw StateError('no such file');
    }
    _files[to] = bytes;
  }

  @override
  Future<int?> size(String name) async => _files[name]?.length;

  @override
  Future<void> remove(String name) async {
    _files.remove(name);
  }

  @override
  Future<List<String>> list() async => _files.keys.toList();
}
