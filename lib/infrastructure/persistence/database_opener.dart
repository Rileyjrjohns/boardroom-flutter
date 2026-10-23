import 'package:drift/drift.dart';

/// A connection as the engine gives it, before it is unlocked: the statements
/// the unlock sends (`exec`, for the ones that take no parameter and answer
/// nothing, which is what `PRAGMA key` is, and `all`, for the ones that answer
/// rows), and the drift executor that the database is then built on.
abstract interface class EngineConnection {
  /// Runs a statement that takes no parameter and whose rows are not wanted.
  Future<void> exec(String sql);

  /// Runs a statement that takes no parameter and returns its rows, by column
  /// name.
  Future<List<Map<String, Object?>>> all(String sql);

  /// Closes the connection. Closing a connection that is closed succeeds.
  Future<void> close();

  /// The executor drift runs on over this connection, once it is unlocked. It
  /// takes the connection over: closing the executor closes the connection.
  QueryExecutor toExecutor();
}

/// The part of an engine that cannot be tested without the native library: its
/// raw calls. `Sqlite3Opener` provides it, over SQLite3MultipleCiphers. It
/// decides nothing: what to do with a key, a file that does not unlock or a
/// file that is in the way is in `unlockDatabase` and `openProtectedDatabase`,
/// which are tested.
///
/// Every method may throw: the callers bound them in time and turn a failure
/// into a result.
abstract interface class DatabaseOpener {
  /// Opens the database file of this name in the private storage of the app,
  /// creating it if it is not there. The connection is not unlocked: no key has
  /// been given to it.
  Future<EngineConnection> open(String name);

  /// Removes the file of a database. Removing a file that is not there
  /// succeeds. Only the main file is promised to go: what the engine keeps
  /// beside it (a journal, which exists only if the app stopped in the middle
  /// of a write) is not. Nothing relies on it: a database is never created
  /// again under the name of one that was removed (see `databaseFileName`).
  Future<void> remove(String name);
}

/// What every connection is set up with once it is open. `secure_delete`
/// overwrites deleted content with zeros, so that a vote that was removed or a
/// cache that was purged does not stay readable in the free pages of the file.
/// The journal is left at its default (a rollback journal that is deleted after
/// each transaction): there is one connection, so nothing is gained from a
/// write-ahead log.
const String connectionPragmas = 'PRAGMA secure_delete = ON';
