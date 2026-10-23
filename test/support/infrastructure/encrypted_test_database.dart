import 'dart:io';

import 'package:boardroom/app/persistence/boardroom_database.dart';
import 'package:boardroom/app/persistence/migrations.dart' as schema;
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/persistence/database_opener.dart';
import 'package:boardroom/core/infrastructure/persistence/migrate.dart';
import 'package:boardroom/core/infrastructure/persistence/protected_database.dart';
import 'package:boardroom/core/infrastructure/persistence/random_key.dart';
import 'package:boardroom/core/infrastructure/persistence/sqlite3_opener.dart';
// Drift has a `DatabaseOpener` of its own, for lazily opened databases.
import 'package:drift/drift.dart' hide DatabaseOpener;
import 'package:test/test.dart';

import '../fakes/fake_monitoring.dart';
import 'database_faults.dart';
import 'memory_secure_storage.dart';
import 'test_database.dart';
import 'test_files.dart';

// Test support, not production code: the database as the app opens it. The
// adapters of the cache and of the outbox run on it for real, in the third run
// of each contract suite: `openProtectedDatabase` makes the key, keeps it in
// the secure storage (a keychain in memory here), and opens a file with
// SQLite3MultipleCiphers, which encrypts it. The engine is made inside
// `openProtectedDatabase`, so the statements are made to fail by an opener that
// puts the faults of the tests between drift and the connection it unlocked.

int _counter = 0;

/// An opener whose connections run the statements of the database through
/// [_faults]. What the unlock sends (the key, the first read) does not go
/// through them, as the migrations do not in the plain runs.
final class _FaultingOpener implements DatabaseOpener {
  new(this._inner, this._faults);

  final DatabaseOpener _inner;
  final DatabaseFaults _faults;

  @override
  Future<EngineConnection> open(String name) async =>
      _FaultingConnection(await _inner.open(name), _faults);

  @override
  Future<void> remove(String name) => _inner.remove(name);
}

final class _FaultingConnection implements EngineConnection {
  new(this._inner, this._faults);

  final EngineConnection _inner;
  final DatabaseFaults _faults;

  @override
  Future<void> exec(String sql) => _inner.exec(sql);

  @override
  Future<List<Map<String, Object?>>> all(String sql) => _inner.all(sql);

  @override
  Future<void> close() => _inner.close();

  @override
  QueryExecutor toExecutor() => _inner.toExecutor().interceptWith(_faults);
}

/// A device: a keychain and a folder of databases, that survive the app being
/// started again.
final class _Device {
  new(Directory parent)
    : directory = Directory('${freshDirectory(parent).path}/databases'),
      name = 'encrypted-${_counter++}.db';

  final Directory directory;
  final String name;
  final MemorySecureStorage storage = MemorySecureStorage();
  final FakeMonitoring monitoring = FakeMonitoring();
}

/// A new database, made like the first start of the app makes it: the key is
/// made and stored, the file is created encrypted, the schema is the latest or
/// the one of [migrations]. It is closed when the test is done, and
/// [TestDatabase.reopen] is a new start of the app, with the key the keychain
/// holds.
Future<TestDatabase> openEncryptedTestDatabase(
  Directory parent, [
  List<Migration>? migrations,
]) => _start(_Device(parent), migrations ?? schema.migrations);

Future<TestDatabase> _start(_Device device, List<Migration> migrations) async {
  // A test opens many databases, one after the other: drift's warning about
  // the same class being instantiated twice is for a program that uses two at
  // once.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final faults = DatabaseFaults();
  final started = await openProtectedDatabase(
    ProtectedDatabaseOptions(
      opener: _FaultingOpener(Sqlite3Opener(device.directory), faults),
      storage: device.storage,
      randomBytes: secureRandomBytes,
      monitoring: device.monitoring,
      name: device.name,
      migrations: migrations,
      databaseFactory: createBoardroomDatabase,
    ),
  );
  final database = switch (started) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError('$error'),
  };
  addTearDown(database.close);
  return TestDatabase(
    database: database,
    faults: faults,
    migrations: migrations,
    file: File('${device.directory.path}/${device.name}'),
    restart: (next) => _start(device, next ?? migrations),
  );
}
