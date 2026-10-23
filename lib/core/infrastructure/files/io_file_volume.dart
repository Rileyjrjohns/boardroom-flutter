import 'dart:io';
import 'dart:typed_data';

import 'package:boardroom/core/infrastructure/files/file_store.dart';

/// The volume of a device, over `dart:io`: as thin as it can be. It renames the
/// calls of the file system to those of [FileVolume], and it is the one file
/// that touches the disk. Its logic is none (the whole-or-nothing write, the
/// names, the time limits and the failures that are values are in
/// `createFileStore`), so its tests only check what it does on a directory of
/// the machine.
final class IoFileVolume implements FileVolume {
  /// Creates the volume of `directory`. `rootUri` is the location the files are
  /// said to have, ending with a slash; by default the `file://` form of the
  /// directory.
  new(this._directory, {String? rootUri})
    : rootUri = rootUri ?? _directory.uri.toString();

  final Directory _directory;

  @override
  final String rootUri;

  File _file(String name) =>
      File('${_directory.path}${Platform.pathSeparator}$name');

  @override
  Future<void> ensureRoot() async {
    await _directory.create(recursive: true);
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    await _file(name).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> move(String from, String to) async {
    await _file(from).rename(_file(to).path);
  }

  @override
  Future<int?> size(String name) async {
    final file = _file(name);
    // ignore: avoid_slow_async_io, the volume is asynchronous like the others.
    return await file.exists() ? await file.length() : null;
  }

  @override
  Future<void> remove(String name) async {
    try {
      await _file(name).delete();
    } on PathNotFoundException {
      // A file that is not there is already gone.
    }
  }

  @override
  Future<List<String>> list() async => [
    await for (final entry in _directory.list(followLinks: false))
      if (entry is File) entry.uri.pathSegments.last,
  ];
}
