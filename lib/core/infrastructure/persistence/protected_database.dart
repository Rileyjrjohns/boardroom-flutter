import 'package:boardroom/app/persistence/boardroom_database.dart';
import 'package:boardroom/app/persistence/migrations.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/persistence/database_key.dart';
import 'package:boardroom/core/infrastructure/persistence/database_opener.dart';
import 'package:boardroom/core/infrastructure/persistence/local_data_reset.dart';
import 'package:boardroom/core/infrastructure/persistence/migrate.dart';
import 'package:boardroom/core/infrastructure/persistence/random_key.dart';
import 'package:boardroom/core/infrastructure/persistence/unlock_database.dart';
import 'package:boardroom/core/infrastructure/secure_storage/secure_storage.dart';
import 'package:boardroom/core/infrastructure/shared/attempt.dart';
import 'package:boardroom/core/infrastructure/shared/serial_queue.dart';
import 'package:meta/meta.dart';

/// How long opening the database, or the keychain, may take before the app
/// gives up.
const int defaultOpenTimeoutMillis = 20000;

/// The code of the error of a database that cannot be had.
const String databaseUnavailableCode = 'databaseUnavailable';

/// Why the local database cannot be had.
enum DatabaseFailureReason implements StableValue {
  /// The keychain cannot be read or written, what it holds for the database is
  /// not a key, or no key can be made: the key cannot be had.
  keyStorage('keyStorage'),

  /// The engine has no encryption: nothing is stored rather than store the data
  /// in clear.
  encryptionUnavailable('encryptionUnavailable'),

  /// The file cannot be opened, though the key is not the reason.
  open('open'),

  /// The schema could not be brought up to date.
  migration('migration'),

  /// The database was written by a more recent version of the app.
  databaseIsNewer('databaseIsNewer');

  new(this.value);

  @override
  final String value;
}

/// The local database cannot be had. Plain data, like every error: the reason,
/// and nothing else.
@immutable
final class DatabaseUnavailable {
  /// Creates the error with its [reason].
  const new(this.reason);

  /// The code of the error.
  String get code => databaseUnavailableCode;

  /// Why the database cannot be had.
  final DatabaseFailureReason reason;

  @override
  bool operator ==(Object other) =>
      other is DatabaseUnavailable && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'DatabaseUnavailable(${reason.value})';
}

/// What `openProtectedDatabase` needs.
@immutable
final class ProtectedDatabaseOptions {
  /// Creates the options.
  const new({
    required this.opener,
    required this.storage,
    required this.randomBytes,
    required this.monitoring,
    required this.name,
    required this.migrations,
    this.timeoutMillis,
  });

  /// Opens the files.
  final DatabaseOpener opener;

  /// Where the key lives.
  final SecureStorage storage;

  /// Where the bits of a key come from: the secure random generator of the
  /// platform.
  final RandomBytes randomBytes;

  /// Where a reset of the database is reported.
  final Monitoring monitoring;

  /// The name of the first database file (see `databaseFileName`).
  final String name;

  /// The steps that bring the schema up to date.
  final List<Migration> migrations;

  /// Defaults to [defaultOpenTimeoutMillis].
  final int? timeoutMillis;

  /// The same options, with another source of bits, another keychain, or
  /// another time limit.
  ProtectedDatabaseOptions copyWith({
    RandomBytes? randomBytes,
    List<Migration>? migrations,
    int? timeoutMillis,
  }) => ProtectedDatabaseOptions(
    opener: opener,
    storage: storage,
    randomBytes: randomBytes ?? this.randomBytes,
    monitoring: monitoring,
    name: name,
    migrations: migrations ?? this.migrations,
    timeoutMillis: timeoutMillis ?? this.timeoutMillis,
  );
}

/// Starts that wait for each other, one queue for each keychain. The key and
/// the file it opens are a state kept in two places; two starts at once on the
/// same keychain would each find no key, each make one, and leave a key that
/// does not open the file the other created. A start runs only when the one
/// before it is over, and finds the state it left.
final Expando<SerialQueue> _startsOfKeychain = Expando('starts of a keychain');

SerialQueue _queueOf(SecureStorage storage) =>
    _startsOfKeychain[storage] ??= createSerialQueue();

/// Opens the local database, protected by a key that only the secure storage
/// holds, and brings its schema up to date. It is the one place that decides
/// what to do with the key. Starts are one at a time for a keychain (see
/// `_startsOfKeychain`).
///
/// - **First start.** There is no key and no file. A key is made (256 random
///   bits from the secure generator of the platform, see `randomKey`), stored
///   first, then the database is created with it. If the app stops in between,
///   the next start finds a key and no file, and creates it.
/// - **Every start after.** The key is read and the database opened with it.
/// - **A keychain that cannot be trusted.** What is stored under the key of the
///   database is there and is not a key: that is a failure of the keychain
///   (`keyStorage`), not a lost key. Nothing is made, set aside or deleted.
/// - **The key is lost** (the keychain was cleared, or the file was restored
///   onto a device whose keychain does not have the key: the key is device-only
///   on purpose) **or rejected** (the file is not the one the key belongs to,
///   or is not a database). The content of the file cannot be read. It is not
///   deleted: the app sets it aside and starts a new database, and everything
///   that was in the old one is not in the new one, votes that had not been
///   sent included.
///   1. The record that local data was reset is written to the keychain (see
///      `local_data_reset.dart`), the first thing, so that whatever happens
///      next, the user is told.
///   2. The key that did not open the file is kept, in another item.
///   3. A new key and the next generation of the file are stored in one write,
///      which is the point of no return: the app now looks for its data in a
///      file of another name (`databaseFileName`), and the one it could not
///      read stays where it is.
///   4. The reset is captured by the monitoring as an error, not as a log.
///   5. Once the new database is open and migrated, the copy that was set aside
///      by the reset before this one, if any, is removed: **at most one copy of
///      an unreadable database is kept**, the latest. There is no rename in the
///      engine, so a name is never reused, which also means a leftover journal
///      of the old file cannot be applied to the new one. It happens at most
///      once in a start. A start that stops anywhere in it finds the state of
///      the last write and goes on from there.
/// - **Rotation.** The key is made once for a file, and replaced only in the
///   case above. Nothing rotates it while the database is in use: that would be
///   `PRAGMA rekey` with the new key written to the keychain first, which no
///   policy of the app asks for (see "Persistence" in docs/design-in-depth.md
///   of the React Native app).
/// - **No encryption.** An engine that cannot encrypt (plain SQLite: the build
///   hook of `sqlite3` was not asked for SQLite3MultipleCiphers) fails the
///   start with `encryptionUnavailable`: confidential data is never written in
///   clear because the build was wrong.
///
/// Never throws. A start that fails with the keychain or the engine is
/// `databaseUnavailable` with the reason; the app then does not start (the
/// container reports it) and nothing is deleted.
Future<Result<BoardroomDatabase, DatabaseUnavailable>> openProtectedDatabase(
  ProtectedDatabaseOptions options,
) => _queueOf(options.storage)(() => _start(options));

Err<Never, DatabaseUnavailable> _unavailable(DatabaseFailureReason reason) =>
    err(DatabaseUnavailable(reason));

Future<Result<BoardroomDatabase, DatabaseUnavailable>> _start(
  ProtectedDatabaseOptions options,
) async {
  final timeout = options.timeoutMillis ?? defaultOpenTimeoutMillis;

  final held = await _readKeyState(options.storage, timeout);
  final KeyState? heldState;
  switch (held) {
    case Err(:final error):
      return err(error);
    case Ok(:final value):
      heldState = value;
  }

  var state = heldState;
  if (state == null) {
    final made = await _makeState(options, firstGeneration, timeout);
    switch (made) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        state = value;
    }
  }

  var opened = await _openUnlocked(
    options.opener,
    databaseFileName(options.name, state.generation),
    state.key,
    timeout,
  );
  int? setAside;
  if (opened case Err(error: UnlockFailure.keyRejected)) {
    final reason = heldState == null
        ? ResetReason.keyLost
        : ResetReason.keyRejected;
    final next = await _setAsideAndRenew(
      options,
      state,
      keepsKey: heldState != null,
      reason: reason,
      timeout: timeout,
    );
    final KeyState renewed;
    switch (next) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        renewed = value;
    }
    setAside = state.generation;
    opened = await _openUnlocked(
      options.opener,
      databaseFileName(options.name, renewed.generation),
      renewed.key,
      timeout,
    );
  }
  final EngineConnection connection;
  switch (opened) {
    case Err(:final error):
      return _unavailable(
        error == UnlockFailure.encryptionUnavailable
            ? DatabaseFailureReason.encryptionUnavailable
            : DatabaseFailureReason.open,
      );
    case Ok(:final value):
      connection = value;
  }

  final prepared = await _prepare(connection, options.migrations);
  final BoardroomDatabase database;
  switch (prepared) {
    case Err():
      return prepared;
    case Ok(:final value):
      database = value;
  }
  if (setAside != null) {
    await _removeOlderCopy(options, setAside, timeout);
  }
  return ok(database);
}

/// Sets the file that could not be read aside and gives the app a new key and
/// the next file, as `openProtectedDatabase` describes. [keepsKey] says whether
/// the key that failed came from the keychain (and is worth keeping) or was
/// made a moment ago for a file that was not there to be found.
Future<Result<KeyState, DatabaseUnavailable>> _setAsideAndRenew(
  ProtectedDatabaseOptions options,
  KeyState current, {
  required bool keepsKey,
  required ResetReason reason,
  required int timeout,
}) async {
  final storage = options.storage;

  if (!await markLocalDataReset(storage, reason, timeout)) {
    return _unavailable(DatabaseFailureReason.keyStorage);
  }
  if (keepsKey) {
    // Best effort: the file is kept either way, and the key only makes it
    // readable if the cause turns out to be somewhere else than the file.
    await attempt(
      () => storage.set(
        SecureStorageKey.databaseKeyPrevious.value,
        formatKeyState(current),
      ),
      timeout,
    );
  }
  final renewed = await _makeState(options, current.generation + 1, timeout);
  if (renewed is Ok) {
    options.monitoring.captureError(
      MonitoringEvent.databaseRecreated,
      storageReadFailed(reason.value),
      {LogAttribute.reason: reason.value},
    );
  }
  return renewed;
}

/// Removes the copy that an earlier reset set aside, now that there is another
/// one. Best effort.
Future<void> _removeOlderCopy(
  ProtectedDatabaseOptions options,
  int setAside,
  int timeout,
) async {
  final older = setAside - 1;
  if (older < firstGeneration) {
    return;
  }
  await attempt(
    () => options.opener.remove(databaseFileName(options.name, older)),
    timeout,
  );
}

/// Opens the file and unlocks it. A file that cannot be opened is `failed`.
Future<Result<EngineConnection, UnlockFailure>> _openUnlocked(
  DatabaseOpener opener,
  String file,
  String key,
  int timeout,
) async {
  final opened = await attempt(() => opener.open(file), timeout);
  final EngineConnection connection;
  switch (opened) {
    case Err():
      return err(UnlockFailure.failed);
    case Ok(:final value):
      connection = value;
  }

  final unlocked = await attempt(
    () => unlockDatabase(connection, key),
    timeout,
  );
  switch (unlocked) {
    case Err():
      await attempt(connection.close, timeout);
      return err(UnlockFailure.failed);
    case Ok(value: Err(:final error)):
      return err(error);
    case Ok():
      return ok(connection);
  }
}

/// Sets the connection up and migrates the schema.
Future<Result<BoardroomDatabase, DatabaseUnavailable>> _prepare(
  EngineConnection connection,
  List<Migration> migrations,
) async {
  try {
    await connection.exec(connectionPragmas);
  } on Object {
    await _closeQuietly(connection);
    return _unavailable(DatabaseFailureReason.open);
  }
  if (!migrationsAreInOrder(migrations)) {
    await _closeQuietly(connection);
    return _unavailable(DatabaseFailureReason.migration);
  }

  final database = BoardroomDatabase(
    connection.toExecutor(),
    migrations: migrations,
  );
  try {
    // The first statement opens the file and runs the migrations.
    await database.customSelect('SELECT 1').get();
    return ok(database);
  } on Object catch (error) {
    await attempt(database.close, defaultOpenTimeoutMillis);
    return _unavailable(
      error is MigrationFailure &&
              error.kind == MigrationFailureKind.databaseIsNewer
          ? DatabaseFailureReason.databaseIsNewer
          : DatabaseFailureReason.migration,
    );
  }
}

Future<void> _closeQuietly(EngineConnection connection) async {
  try {
    await connection.close();
  } on Object {
    // Nothing more can be done for a database that does not close.
  }
}

/// The state in the keychain, or `null` when there is none. An item that is
/// there and is not a state is a failure of the keychain: starting over would
/// set aside a database that a key opens.
Future<Result<KeyState?, DatabaseUnavailable>> _readKeyState(
  SecureStorage storage,
  int timeout,
) async {
  final read = await attempt(
    () => storage.get(SecureStorageKey.databaseKey.value),
    timeout,
  );
  switch (read) {
    case Err():
      return _unavailable(DatabaseFailureReason.keyStorage);
    case Ok(value: null):
      return ok<KeyState?>(null);
    case Ok(:final value?):
      final state = parseKeyState(value);
      if (state == null) {
        return _unavailable(DatabaseFailureReason.keyStorage);
      }
      return ok<KeyState?>(state);
  }
}

/// Makes a key and stores it with the generation. The key is used only once it
/// is safe in the keychain.
Future<Result<KeyState, DatabaseUnavailable>> _makeState(
  ProtectedDatabaseOptions options,
  int generation,
  int timeout,
) async {
  final made = await _randomKey(options.randomBytes, timeout);
  final String key;
  switch (made) {
    case Err(:final error):
      return err(error);
    case Ok(:final value):
      key = value;
  }

  final state = KeyState(generation: generation, key: key);
  final stored = await attempt(
    () => options.storage.set(
      SecureStorageKey.databaseKey.value,
      formatKeyState(state),
    ),
    timeout,
  );
  if (stored is Err) {
    return _unavailable(DatabaseFailureReason.keyStorage);
  }
  return ok(state);
}

/// 256 random bits as hexadecimal digits (`keyFromBytes`), drawn from the
/// secure generator of the platform that the options hand over. That generator
/// throws when it cannot do its job, and never answers with weaker bytes, so
/// there is nothing to detect here but an answer that is not a key: which is a
/// failure of the key storage like any other, and nothing is made, stored or
/// opened.
Future<Result<String, DatabaseUnavailable>> _randomKey(
  RandomBytes randomBytes,
  int timeout,
) async {
  final drawn = await attempt(() => randomBytes(keyBytes), timeout);
  final key = switch (drawn) {
    Ok(:final value) => keyFromBytes(value),
    Err() => null,
  };
  if (key == null) {
    return _unavailable(DatabaseFailureReason.keyStorage);
  }
  return ok(key);
}
