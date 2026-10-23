import 'dart:math';
import 'dart:typed_data';

import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/infrastructure/shared/attempt.dart';
import 'package:meta/meta.dart';

// The seam between what the app keeps in files (the content of the documents
// already viewed) and the file system under it. The adapters are written
// against `FileStore`: write a file whole or not at all, ask whether it is
// there
// and how big it is, delete it, delete everything. It is made by
// `createFileStore` from a `FileVolume`, which is what a file system provides:
// a directory, and a handful of raw calls that may throw. Two volumes sit
// behind it: the one of `dart:io` on a device (`IoFileVolume`) and the one in
// memory in the tests (`test/infrastructure/support/memory_file_volume.dart`).

/// How long a call may take before it counts as failed. The files are small and
/// local.
const int defaultFileTimeoutMillis = 10000;

/// What a name is made of: letters, digits, dots, dashes and underscores, and
/// no
/// path.
final RegExp _nameFormat = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

/// The suffix of a file that is being written. A file is written under a name
/// of its own and moved onto its name when it is whole, so a name that ends
/// with
/// this is never a file of the store.
const String partialSuffix = '.part';

const String _separator = '/';
const String _invalidNameCause = 'invalid file name';
const int _instantNameLength = 8;
const int _base36 = 36;

/// Whether [name] is made of one segment of safe characters, which is all a
/// name
/// has to be.
bool _hasNameFormat(String name) => _nameFormat.hasMatch(name);

/// Whether [name] is the name of a file that was being written.
bool isPartialFileName(String name) => name.endsWith(partialSuffix);

/// Whether [name] can be the name of a file of the store: one segment, of safe
/// characters, not a partial file.
bool isValidFileName(String name) =>
    _hasNameFormat(name) && !isPartialFileName(name);

/// Why a call on the store failed: a kind of failure, never a path, a name or a
/// message.
@immutable
final class FileStoreFailure {
  /// Creates the failure of a call, with the [cause] to report.
  const new({required this.cause});

  /// A kind of failure, safe to keep (see `describeFailure`).
  final String cause;

  @override
  bool operator ==(Object other) =>
      other is FileStoreFailure && other.cause == cause;

  @override
  int get hashCode => cause.hashCode;

  @override
  String toString() => 'FileStoreFailure($cause)';
}

/// A file of the store.
@immutable
final class StoredFile {
  /// Creates the description of a file of [size] bytes.
  const new({required this.size});

  /// The size of the file, in bytes.
  final int size;

  @override
  bool operator ==(Object other) => other is StoredFile && other.size == size;

  @override
  int get hashCode => size.hashCode;

  @override
  String toString() => 'StoredFile($size)';
}

/// Files in one directory of the app, by name. No call throws, and every one
/// settles in bounded time. A name is one segment of letters, digits, dots,
/// dashes and underscores (see [isValidFileName]); any other is a failure, so a
/// name that comes from outside can never reach a directory above the store.
/// The names of the files that were being written ([partialSuffix]) are the
/// store's own: they are listed and can be deleted, so that what a write that
/// was interrupted left can be cleaned up, but they cannot be written or looked
/// at.
abstract interface class FileStore {
  /// Where the file of this name is, as the location the viewer opens. Nothing
  /// is read.
  String uriOf(String name);

  /// The name of the file a location points at, or `null` when it is not one of
  /// this store.
  String? nameOf(String uri);

  /// Writes the file whole or not at all: the bytes go to a file of their own
  /// and are moved onto the name only when all of them are written, so a reader
  /// never finds half a file, and a failure leaves the previous file, if any,
  /// as
  /// it was. Writing a name again replaces its file.
  Future<Result<void, FileStoreFailure>> write(String name, Uint8List bytes);

  /// The file of this name, or `null` when there is no such file.
  Future<Result<StoredFile?, FileStoreFailure>> stat(String name);

  /// Deleting a file that is not there succeeds. A file that was being written
  /// can be deleted too.
  Future<Result<void, FileStoreFailure>> delete(String name);

  /// The names of everything in the store, files that were being written
  /// included.
  Future<Result<List<String>, FileStoreFailure>> list();

  /// Deletes every file, and goes on after one that cannot be deleted so that
  /// it
  /// takes as many with it as it can. Fails if any file is left.
  Future<Result<void, FileStoreFailure>> deleteAll();
}

/// What a file system provides, raw: its calls may throw, and nothing is
/// checked. [createFileStore] adds the rest.
abstract interface class FileVolume {
  /// The location of the directory, ending with a slash.
  String get rootUri;

  /// Makes the directory, and the ones above it, if they are not there.
  /// Succeeds if it is.
  Future<void> ensureRoot();

  /// Writes the bytes to the file, which it creates or empties.
  Future<void> write(String name, Uint8List bytes);

  /// Renames [from] to [to], replacing the file [to] if there is one.
  Future<void> move(String from, String to);

  /// The size of the file, or `null` when there is none.
  Future<int?> size(String name);

  /// Deletes the file. A file that is not there is not an error.
  Future<void> remove(String name);

  /// The names of the files of the directory.
  Future<List<String>> list();
}

/// The store of a volume. All the logic is here, so that the volumes only have
/// to provide the raw calls: the check of the names, the write that is whole or
/// nothing, the failures that are values, and the time that is bounded.
/// [timeoutMillis] defaults to [defaultFileTimeoutMillis].
FileStore createFileStore(
  FileVolume volume, {
  int timeoutMillis = defaultFileTimeoutMillis,
}) => _FileStore(volume, timeoutMillis);

final class _FileStore implements FileStore {
  new(this._volume, this._timeout);

  final FileVolume _volume;
  final int _timeout;
  var _partials = 0;

  // Two stores over the same directory (a restart in a test, say) must not name
  // a partial file alike.
  final String _instance = List.generate(
    _instantNameLength,
    (_) => Random().nextInt(_base36).toRadixString(_base36),
  ).join();

  Future<Result<T, FileStoreFailure>> _run<T>(Future<T> Function() work) async {
    final done = await attempt(work, _timeout);
    switch (done) {
      case Ok(:final value):
        return ok(value);
      case Err(:final error):
        return err(FileStoreFailure(cause: error.cause));
    }
  }

  /// [work] for a name that is acceptable, or the failure of a name that is
  /// not.
  Future<Result<T, FileStoreFailure>> _runForName<T>(
    bool acceptable,
    Future<T> Function() work,
  ) {
    if (!acceptable) {
      return Future.value(
        err(const FileStoreFailure(cause: _invalidNameCause)),
      );
    }
    return _run(work);
  }

  @override
  String uriOf(String name) => '${_volume.rootUri}$name';

  @override
  String? nameOf(String uri) {
    if (!uri.startsWith(_volume.rootUri)) {
      return null;
    }
    final name = uri.substring(_volume.rootUri.length);
    return !name.contains(_separator) && isValidFileName(name) ? name : null;
  }

  @override
  Future<Result<void, FileStoreFailure>> write(String name, Uint8List bytes) =>
      _runForName(isValidFileName(name), () async {
        await _volume.ensureRoot();
        _partials += 1;
        final partial = '$name.$_instance$_partials$partialSuffix';
        try {
          await _volume.write(partial, bytes);
          await _volume.move(partial, name);
        } on Object {
          // What is left of a write that failed must not stay: best effort, the
          // failure is the write's.
          try {
            await _volume.remove(partial);
          } on Object {
            // The write failed first; that is the failure to report.
          }
          rethrow;
        }
      });

  @override
  Future<Result<StoredFile?, FileStoreFailure>> stat(String name) =>
      _runForName(isValidFileName(name), () async {
        final size = await _volume.size(name);
        return size == null ? null : StoredFile(size: size);
      });

  @override
  Future<Result<void, FileStoreFailure>> delete(String name) =>
      _runForName(_hasNameFormat(name), () => _volume.remove(name));

  @override
  Future<Result<List<String>, FileStoreFailure>> list() => _run(() async {
    await _volume.ensureRoot();
    return await _volume.list();
  });

  @override
  Future<Result<void, FileStoreFailure>> deleteAll() => _run(() async {
    await _volume.ensureRoot();
    Object? firstFailure;
    StackTrace? firstTrace;
    for (final name in await _volume.list()) {
      try {
        await _volume.remove(name);
      } on Object catch (error, trace) {
        if (firstFailure == null) {
          firstFailure = error;
          firstTrace = trace;
        }
      }
    }
    // The first failure as it came: the code it carries is what the failure is
    // reported as.
    if (firstFailure != null) {
      Error.throwWithStackTrace(firstFailure, firstTrace!);
    }
  });
}
