import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:boardroom/infrastructure/files/file_store.dart';

// Test support, not production code: a volume that fails when the test says so,
// to check that the store and the adapters over it turn a file system that
// fails into the errors of their ports and leave the files as they were.

/// The calls of a volume that can be made to fail.
enum VolumeCall {
  /// `ensureRoot`.
  ensureRoot,

  /// `write`.
  write,

  /// `move`.
  move,

  /// `size`.
  size,

  /// `remove`.
  remove,

  /// `list`.
  list,
}

/// The number of the error a failing call carries: `EIO` on the platforms of
/// the project.
const int ioErrorNumber = 5;

/// A volume that fails or hangs on demand.
final class FaultyFileVolume implements FileVolume {
  /// Creates a volume that forwards to [_inner].
  new(this._inner);

  final FileVolume _inner;
  final Set<VolumeCall> _failing = {};
  final Set<VolumeCall> _hanging = {};

  /// How many times each call was made, failed ones included.
  final Map<VolumeCall, int> calls = {
    for (final call in VolumeCall.values) call: 0,
  };

  @override
  String get rootUri => _inner.rootUri;

  /// While set, the call fails with an error that carries a code, as the file
  /// system's do.
  // ignore: avoid_positional_boolean_parameters
  void fail(VolumeCall call, bool failing) {
    if (failing) {
      _failing.add(call);
    } else {
      _failing.remove(call);
    }
  }

  /// While set, the call never answers.
  // ignore: avoid_positional_boolean_parameters
  void hang(VolumeCall call, bool hanging) {
    if (hanging) {
      _hanging.add(call);
    } else {
      _hanging.remove(call);
    }
  }

  @override
  Future<void> ensureRoot() => _guard(VolumeCall.ensureRoot, _inner.ensureRoot);

  @override
  Future<void> write(String name, Uint8List bytes) =>
      _guard(VolumeCall.write, () => _inner.write(name, bytes));

  @override
  Future<void> move(String from, String to) =>
      _guard(VolumeCall.move, () => _inner.move(from, to));

  @override
  Future<int?> size(String name) =>
      _guard(VolumeCall.size, () => _inner.size(name));

  @override
  Future<void> remove(String name) =>
      _guard(VolumeCall.remove, () => _inner.remove(name));

  @override
  Future<List<String>> list() => _guard(VolumeCall.list, _inner.list);

  Future<T> _guard<T>(VolumeCall call, Future<T> Function() send) {
    calls[call] = calls[call]! + 1;
    if (_hanging.contains(call)) {
      return Completer<T>().future;
    }
    if (_failing.contains(call)) {
      return Future.error(
        FileSystemException(
          '${call.name} failed',
          '/secret/path',
          const OSError('Input/output error', ioErrorNumber),
        ),
      );
    }
    return send();
  }
}
