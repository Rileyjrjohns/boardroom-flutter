import 'dart:async';
import 'dart:io';

import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// Why `attempt` gave no value.
enum AttemptFailureKind implements StableValue {
  /// The work threw or rejected.
  failed('failed'),

  /// The work did not settle in time.
  timedOut('timedOut');

  new(this.value);

  @override
  final String value;
}

/// What `attempt` gives when the work failed or took too long.
@immutable
final class AttemptFailure {
  /// Creates a failure of the given [kind] with a [cause] safe to keep.
  const new({required this.kind, required this.cause});

  /// Whether the work failed or timed out.
  final AttemptFailureKind kind;

  /// A kind of failure, safe to put in the `cause` of an error: see
  /// [describeFailure].
  final String cause;

  @override
  bool operator ==(Object other) =>
      other is AttemptFailure && other.kind == kind && other.cause == cause;

  @override
  int get hashCode => Object.hash(kind, cause);

  @override
  String toString() => 'AttemptFailure(${kind.value}, $cause)';
}

/// What a failure that carries no code is reported as.
const String unknownFailure = 'unknown failure';

/// The cause of a call that did not settle in time.
const String timeoutCause = 'timeout';

/// What a code a plugin reports must look like to be kept: capital letters,
/// digits and underscores (`ERR_ACTIVITY`), so that free text never gets in.
final RegExp _codeFormat = RegExp(r'^[A-Z][A-Z0-9_]{0,63}$');

/// A diagnostic for a failure of a native module or of a database, safe to
/// keep: the code the failure carries when it has one (the result code of
/// SQLite, the error number of the operating system, the code of a failure of
/// a plugin when it is written like a code), and nothing else. Their
/// messages are left out on purpose: they can quote the statement, a path or a
/// value.
String describeFailure(Object? error) => switch (error) {
  SqliteException(:final resultCode) => 'sqlite error $resultCode',
  PlatformException(:final code) when _codeFormat.hasMatch(code) => code,
  FileSystemException(osError: OSError(:final errorCode)) =>
    'os error $errorCode',
  _ => unknownFailure,
};

/// Runs asynchronous work that can fail or hang, and settles in bounded time:
/// with the value, with the failure, or with a timeout. It is how the adapters
/// of the device keep the promise of the ports that every call settles,
/// whatever the native side does. Work that is still running when the time is
/// up is left to finish, and what it ends with is ignored.
Future<Result<T, AttemptFailure>> attempt<T>(
  Future<T> Function() work,
  int timeoutMillis,
) async {
  final expired = Completer<void>();
  final timer = Timer(Duration(milliseconds: timeoutMillis), expired.complete);
  try {
    final outcome = await Future.any<Result<T, AttemptFailure>>([
      work().then<Result<T, AttemptFailure>>(ok),
      expired.future.then(
        (_) => err(
          const AttemptFailure(
            kind: AttemptFailureKind.timedOut,
            cause: timeoutCause,
          ),
        ),
      ),
    ]);
    return outcome;
  } on Object catch (error) {
    return err(
      AttemptFailure(
        kind: AttemptFailureKind.failed,
        cause: describeFailure(error),
      ),
    );
  } finally {
    timer.cancel();
  }
}
