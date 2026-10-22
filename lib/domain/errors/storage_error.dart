part of 'app_error.dart';

/// The codes of the storage errors.
enum StorageErrorCode implements StableValue {
  /// The local store could not be read.
  readFailed('storageReadFailed'),

  /// The local store could not be written.
  writeFailed('storageWriteFailed');

  new(this.value);

  @override
  final String value;
}

/// What the local store can fail with.
sealed class StorageError extends AppError {
  /// Creates a storage error, with a [cause] when there is one to report.
  const new({this.cause});

  /// The technical diagnostic, or null. It is for the monitoring tools, never
  /// shown to the user, and it is a kind of failure, nothing else: never a file
  /// path, a URL, the location of a document or its title, a name, an email,
  /// nor the choice of a vote.
  final String? cause;

  @override
  Map<String, Object?> get payload =>
      cause == null ? const {} : {'cause': cause};
}

/// The local store could not be read. A miss is not an error: a cache returns
/// it as a value.
final class StorageReadFailedError extends StorageError {
  /// Creates the error, with a [cause] when there is one to report.
  const new({super.cause});

  @override
  String get code => StorageErrorCode.readFailed.value;
}

/// The local store could not be written.
final class StorageWriteFailedError extends StorageError {
  /// Creates the error, with a [cause] when there is one to report.
  const new({super.cause});

  @override
  String get code => StorageErrorCode.writeFailed.value;
}

/// Builds a [StorageReadFailedError], with the technical [cause] when there is
/// one.
StorageReadFailedError storageReadFailed([String? cause]) =>
    StorageReadFailedError(cause: cause);

/// Builds a [StorageWriteFailedError], with the technical [cause] when there is
/// one.
StorageWriteFailedError storageWriteFailed([String? cause]) =>
    StorageWriteFailedError(cause: cause);
