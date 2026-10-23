import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/infrastructure/shared/attempt.dart';
import 'package:drift/drift.dart'
    show CouldNotRollBackException, DriftWrappedException;

/// How long a statement may take before the call is a storage failure.
const int defaultStatementTimeoutMillis = 10000;

/// The failure of the database engine a failure stands for. Drift wraps a
/// failure of the engine in two cases (a statement it explains, and a
/// transaction that could not be rolled back after the work failed); the
/// failure to report is the one underneath, whose code `describeFailure`
/// knows.
Object engineFailureOf(Object failure) => switch (failure) {
  DriftWrappedException(:final cause?) => cause,
  CouldNotRollBackException(:final cause) => cause,
  _ => failure,
};

/// Runs [work] and lets it fail with what the database engine failed with
/// (see [engineFailureOf]).
Future<T> _failingAsTheEngineDid<T>(Future<T> Function() work) async {
  try {
    return await work();
  } on Object catch (error, trace) {
    Error.throwWithStackTrace(engineFailureOf(error), trace);
  }
}

/// `attempt` for work on the database: it settles in bounded time, with the
/// value, or with the failure of the engine (see `describeFailure`), or with a
/// timeout.
Future<Result<T, AttemptFailure>> attemptOnDatabase<T>(
  Future<T> Function() work,
  int timeoutMillis,
) => attempt(() => _failingAsTheEngineDid(work), timeoutMillis);

/// Runs work against the database for a read: whatever goes wrong, in bounded
/// time, is a `storageReadFailed` whose cause is a kind of failure (see
/// `describeFailure`), never a statement, a path or a value.
Future<Result<T, StorageReadFailedError>> guardedRead<T>(
  Future<T> Function() work,
  int timeoutMillis,
) async {
  final done = await attemptOnDatabase(work, timeoutMillis);
  switch (done) {
    case Ok(:final value):
      return ok(value);
    case Err(:final error):
      return err(storageReadFailed(error.cause));
  }
}

/// The same, for a write.
Future<Result<T, StorageWriteFailedError>> guardedWrite<T>(
  Future<T> Function() work,
  int timeoutMillis,
) async {
  final done = await attemptOnDatabase(work, timeoutMillis);
  switch (done) {
    case Ok(:final value):
      return ok(value);
    case Err(:final error):
      return err(storageWriteFailed(error.cause));
  }
}
