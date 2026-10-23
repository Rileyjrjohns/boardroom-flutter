import 'dart:io';

import 'package:boardroom/infrastructure/persistence/boardroom_database.dart';
import 'package:boardroom/infrastructure/persistence/migrations.dart' as schema;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'database_faults.dart';
import 'test_files.dart';

// Test support, not production code: a real SQLite database at the latest
// version of the schema, in memory or in a file of a temporary directory, whose
// statements can be made to fail, and which can be closed and opened again like
// the app being stopped and started. The files are not encrypted: the key is
// the business of `openProtectedDatabase`, which the tests of the protected
// database run for real (SQLite3MultipleCiphers refuses a key on a database in
// memory). The adapters also run on the database that `openProtectedDatabase`
// gives, encrypted for real: see `encrypted_test_database.dart`.

/// A database of the tests.
final class TestDatabase {
  /// Creates the description of an open database.
  const new({
    required this.database,
    required this.faults,
    required this.migrations,
    this.file,
    this.restart,
  });

  /// The database, migrated.
  final BoardroomDatabase database;

  /// Makes the statements fail.
  final DatabaseFaults faults;

  /// The migrations it was opened with.
  final List<schema.Migration> migrations;

  /// The file of the database; `null` for a database in memory.
  final File? file;

  /// How a start of the app opens this database again, with the migrations it
  /// is given (`null`: the same). `null` for a database that is opened as a
  /// plain file of the tests.
  final Future<TestDatabase> Function(List<schema.Migration>? next)? restart;

  /// Closes this database and opens the same file again, as a new start of the
  /// app would, with the same migrations or with [next] (a newer version of the
  /// app). A database in memory has no file to open again.
  Future<TestDatabase> reopen([List<schema.Migration>? next]) async {
    final file = this.file;
    if (file == null) {
      throw StateError('A database in memory cannot be opened again.');
    }
    await database.close();
    final restart = this.restart;
    if (restart != null) {
      return await restart(next);
    }
    return await openTestFile(file, next ?? migrations);
  }
}

int _counter = 0;

/// A new database migrated to the latest version, or to [migrations]: in
/// memory, or, with a [directory], an empty file of its own in it. It is closed
/// when the test is done.
Future<TestDatabase> openTestDatabase([
  Directory? directory,
  List<schema.Migration>? migrations,
]) async {
  if (directory == null) {
    return await _open(
      NativeDatabase.memory(),
      migrations ?? schema.migrations,
    );
  }
  _counter += 1;
  return await openTestFile(
    File('${directory.path}/test-$_counter.db'),
    migrations,
  );
}

/// The file [file] (made if it is not there) opened with [migrations]. It is
/// closed when the test is done. It throws what the migrations throw when one
/// fails.
Future<TestDatabase> openTestFile(
  File file, [
  List<schema.Migration>? migrations,
]) async => await _open(
  NativeDatabase(file),
  migrations ?? schema.migrations,
  file: file,
);

Future<TestDatabase> _open(
  QueryExecutor executor,
  List<schema.Migration> migrations, {
  File? file,
}) async {
  // A test opens many databases, one after the other: drift's warning about
  // the same class being instantiated twice is for a program that uses two at
  // once.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final faults = DatabaseFaults();
  final database = BoardroomDatabase(
    executor.interceptWith(faults),
    migrations: migrations,
  );
  addTearDown(database.close);
  // The first statement opens the file and runs the migrations.
  await database.customSelect('SELECT 1').get();
  return TestDatabase(
    database: database,
    faults: faults,
    migrations: migrations,
    file: file,
  );
}

/// The directory of the databases of the test file that calls this, removed
/// when the file is done. Call it at the top of `main`.
Directory databaseDirectory() => temporaryDirectory();

/// Raw statements, for the tests that look at the rows behind the back of the
/// adapters, or wreck them.
extension RawStatements on BoardroomDatabase {
  /// Runs a statement and returns nothing.
  Future<void> run(String sql, [List<Object?> args = const []]) async {
    await customStatement(sql, args);
  }

  /// Runs a statement and returns its rows, by column name.
  Future<List<Map<String, Object?>>> all(
    String sql, [
    List<Object?> args = const [],
  ]) async => [
    for (final row in await customSelect(
      sql,
      variables: [for (final arg in args) _variableOf(arg)],
    ).get())
      row.data,
  ];
}

Variable<Object> _variableOf(Object? value) => switch (value) {
  String() => Variable.withString(value),
  int() => Variable.withInt(value),
  double() => Variable.withReal(value),
  _ => const Variable<Object>(null),
};
