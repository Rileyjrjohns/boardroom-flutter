import 'dart:io';

import 'package:boardroom/core/infrastructure/persistence/database_opener.dart';
// Drift has a `DatabaseOpener` of its own, for lazily opened databases.
import 'package:drift/drift.dart' hide DatabaseOpener;
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

// The device side of the database: `sqlite3`, whose build hook bundles
// SQLite3MultipleCiphers (`hooks.user_defines` in pubspec.yaml), and drift's
// `NativeDatabase` over the connection it opened. It is as thin as it can be:
// raw calls and nothing that decides anything. What to do with a key, with a
// file that does not unlock and with a file in the way is in `unlockDatabase`
// and `openProtectedDatabase`.

/// The name of the folder of the databases, in the private storage of the app.
const String databaseDirectoryName = 'boardroom-databases';

final class _Sqlite3Connection implements EngineConnection {
  new(this._database);

  final Database _database;

  @override
  Future<void> exec(String sql) async {
    _database.execute(sql);
  }

  @override
  Future<List<Map<String, Object?>>> all(String sql) async => [
    for (final row in _database.select(sql)) Map.of(row),
  ];

  @override
  Future<void> close() async {
    _database.close();
  }

  @override
  QueryExecutor toExecutor() => NativeDatabase.opened(_database);
}

/// Opens the database files of a directory, with SQLite3MultipleCiphers.
final class Sqlite3Opener implements DatabaseOpener {
  /// Creates an opener of the files of [directory]. The directory is made when
  /// the first file is opened.
  const new(this.directory);

  /// Where the files are.
  final Directory directory;

  File _fileOf(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  @override
  Future<EngineConnection> open(String name) async {
    await directory.create(recursive: true);
    return _Sqlite3Connection(sqlite3.open(_fileOf(name).path));
  }

  @override
  Future<void> remove(String name) async {
    final file = _fileOf(name);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}

/// The opener of the device: the files are in the private storage of the app
/// (`getApplicationSupportDirectory`), which the backups of the system leave
/// out on Android (`allowBackup` is off) and which no other app reads. [locate]
/// stands for the storage in tests.
Future<DatabaseOpener> createDeviceDatabaseOpener({
  Future<Directory> Function()? locate,
}) async {
  final parent = await (locate ?? getApplicationSupportDirectory)();
  return Sqlite3Opener(
    Directory('${parent.path}${Platform.pathSeparator}$databaseDirectoryName'),
  );
}
