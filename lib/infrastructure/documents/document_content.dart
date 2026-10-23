import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/document_location.dart';
import 'package:boardroom/infrastructure/files/file_store.dart';

// What the document caches ask of the files, by location. A location is the
// opaque reference that the repository handed out; the store reads the name of
// the file out of it. A location that is not a file of the store (a leftover of
// an earlier version of the app, a reference to somewhere else) has no content
// here: nothing to find, and nothing to delete.

/// Whether the content a location points at is on the device. A location that
/// is no file of the store has none.
Future<Result<bool, FileStoreFailure>> contentExists(
  FileStore files,
  DocumentLocation location,
) async {
  final name = files.nameOf(location);
  if (name == null) {
    return ok(false);
  }
  final stat = await files.stat(name);
  switch (stat) {
    case Ok(:final value):
      return ok(value != null);
    case Err(:final error):
      return err(error);
  }
}

/// Deletes the content a location points at. What is not there, or is not a
/// file of the store, is already gone.
Future<Result<void, FileStoreFailure>> deleteContent(
  FileStore files,
  DocumentLocation location,
) async {
  final name = files.nameOf(location);
  return name == null ? ok<void>(null) : await files.delete(name);
}
