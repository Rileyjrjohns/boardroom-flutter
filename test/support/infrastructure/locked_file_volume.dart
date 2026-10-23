import 'dart:io';
import 'dart:typed_data';

import 'package:boardroom/core/infrastructure/files/file_store.dart';

// Test support, not production code: a volume where some files cannot be
// deleted (a file another process holds open), to check that the callers go on
// with the files they can delete and report the one they cannot.

/// The number of the error a locked file carries: `EBUSY` on the platforms of
/// the project.
const int busyErrorNumber = 16;

/// A volume that refuses to delete the files it is told are locked.
final class LockedFileVolume implements FileVolume {
  /// Creates a volume that forwards to [_inner].
  new(this._inner);

  final FileVolume _inner;
  final Set<String> _locked = {};

  /// The file of this name cannot be deleted from now on.
  void lock(String name) {
    _locked.add(name);
  }

  @override
  String get rootUri => _inner.rootUri;

  @override
  Future<void> ensureRoot() => _inner.ensureRoot();

  @override
  Future<void> write(String name, Uint8List bytes) => _inner.write(name, bytes);

  @override
  Future<void> move(String from, String to) => _inner.move(from, to);

  @override
  Future<int?> size(String name) => _inner.size(name);

  @override
  Future<void> remove(String name) {
    if (_locked.contains(name)) {
      return Future.error(
        const FileSystemException(
          'locked',
          '/secret/path',
          OSError('Resource busy', busyErrorNumber),
        ),
      );
    }
    return _inner.remove(name);
  }

  @override
  Future<List<String>> list() => _inner.list();
}
