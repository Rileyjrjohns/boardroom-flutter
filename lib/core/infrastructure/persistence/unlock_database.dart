import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/persistence/database_key.dart';
import 'package:boardroom/core/infrastructure/persistence/database_opener.dart';
import 'package:boardroom/core/infrastructure/shared/attempt.dart';

/// Why a database could not be unlocked.
enum UnlockFailure implements StableValue {
  /// The file exists and the key does not open it: it was written with another
  /// key, or it is not a database.
  keyRejected('keyRejected'),

  /// The engine cannot encrypt: it is plain SQLite, and nothing is written.
  encryptionUnavailable('encryptionUnavailable'),

  /// Anything else: the file cannot be read, the storage is full.
  failed('failed');

  new(this.value);

  @override
  final String value;
}

/// What SQLite says when a file is not a database, which is what a wrong key
/// looks like.
final RegExp _notADatabase = RegExp('not a database', caseSensitive: false);

/// The result code of the same failure, `SQLITE_NOTADB`, for an engine that
/// gives it.
const String _notADatabaseCode = 'sqlite error 26';

/// Selects the cipher whose files SQLCipher 4 reads and writes. The engine
/// (SQLite3MultipleCiphers) has several, and the one it starts with is another.
const String selectCipher = "PRAGMA cipher = 'sqlcipher'";

/// `PRAGMA` takes no parameter, so the key is part of the statement, as a raw
/// key.
String _unlockWith(String key) => 'PRAGMA key = "x\'$key\'"';

/// The engine answers the cipher it uses. Plain SQLite does not know the
/// pragma, and answers nothing.
const String cipherProbe = 'PRAGMA cipher';

/// The first read of the file: with a wrong key, it is where SQLite finds out
/// it is not a database.
const String readSchema = 'SELECT count(*) FROM sqlite_master';

/// Unlocks an open connection with the key, and reads the file once to find out
/// the key opens it. It is where the engine's answers are turned into a
/// decision:
///
/// - the key is checked to be nothing but the 64 digits it should be before it
///   reaches a statement;
/// - an engine that does not answer a cipher is plain SQLite, which would
///   ignore the key and write in clear: `encryptionUnavailable`;
/// - "file is not a database" (the message, or its result code) is
///   `keyRejected`: SQLite cannot tell a wrong key from a file that is not a
///   database, and the callers do not need it to;
/// - anything else is `failed`.
///
/// A connection that does not unlock is closed; one that does is the caller's
/// to close. It never throws.
Future<Result<void, UnlockFailure>> unlockDatabase(
  EngineConnection connection,
  String key,
) async {
  if (!keyFormat.hasMatch(key)) {
    await _closeQuietly(connection);
    return err(UnlockFailure.failed);
  }

  try {
    await connection.exec(selectCipher);
    await connection.exec(_unlockWith(key));
    if ((await connection.all(cipherProbe)).isEmpty) {
      await _closeQuietly(connection);
      return err(UnlockFailure.encryptionUnavailable);
    }
    await connection.all(readSchema);
    return ok<void>(null);
  } on Object catch (error) {
    await _closeQuietly(connection);
    return err(
      _isNotADatabase(error) ? UnlockFailure.keyRejected : UnlockFailure.failed,
    );
  }
}

bool _isNotADatabase(Object error) {
  if (error is Exception && _notADatabase.hasMatch('$error')) {
    return true;
  }
  return describeFailure(error) == _notADatabaseCode;
}

Future<void> _closeQuietly(EngineConnection connection) async {
  try {
    await connection.close();
  } on Object {
    // Nothing more can be done for a database that does not close.
  }
}
