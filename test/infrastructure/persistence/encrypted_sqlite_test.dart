import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../support/test_files.dart';

// What the project relies on for the encryption at rest of the local database
// (docs/security.md of the React Native app: SQLCipher, the key in the secure
// storage): the build hook of `sqlite3` is asked for SQLite3MultipleCiphers
// (`hooks.user_defines` in pubspec.yaml), whose `sqlcipher` cipher reads and
// writes SQLCipher 4 databases. These tests open a database on disk, with and
// without the key, through `sqlite3` and through `drift`, on the machine that
// runs the tests: the proof that the native library the tests (and CI) load
// can encrypt. They have no React Native counterpart.

const String _secret = 'SECRET-VALUE-NOBODY-MAY-READ';
const String _cipher = "PRAGMA cipher = 'sqlcipher'";

/// A key as the project writes it: 32 bytes as 64 hexadecimal digits, which
/// the cipher takes as the key itself, with no derivation.
final String _key = List.generate(
  32,
  (index) => index.toRadixString(16).padLeft(2, '0'),
).join();
final String _otherKey = List.generate(
  32,
  (index) => (255 - index).toRadixString(16).padLeft(2, '0'),
).join();

String _pragmaKey(String key) => 'PRAGMA key = "x\'$key\'"';

void _unlock(sqlite.Database database, String key) {
  database
    ..execute(_cipher)
    ..execute(_pragmaKey(key));
}

void main() {
  final parent = temporaryDirectory();

  File aDatabaseFile() => File('${freshDirectory(parent).path}/boardroom.db');

  group('the native library of the tests', () {
    test('is SQLite3MultipleCiphers', () {
      final database = sqlite.sqlite3.openInMemory();
      addTearDown(database.close);

      final version = database.select('SELECT sqlite3mc_version() AS version');

      expect(version.single['version'], contains('SQLite3 Multiple Ciphers'));
    });

    test('writes a database nobody can read without the key', () {
      final file = aDatabaseFile();
      final database = sqlite.sqlite3.open(file.path);
      _unlock(database, _key);
      database
        ..execute('CREATE TABLE secrets (value TEXT NOT NULL)')
        ..execute('INSERT INTO secrets (value) VALUES (?)', [_secret])
        ..close();

      final bytes = file.readAsBytesSync();
      expect(String.fromCharCodes(bytes), isNot(contains(_secret)));
      expect(
        String.fromCharCodes(bytes.take(15)),
        isNot(equals('SQLite format 3')),
      );

      final withoutKey = sqlite.sqlite3.open(file.path);
      addTearDown(withoutKey.close);
      expect(
        () => withoutKey.select('SELECT value FROM secrets'),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('reads the database back with the key it was written with', () {
      final file = aDatabaseFile();
      sqlite.sqlite3.open(file.path)
        ..let(_unlock, _key)
        ..execute('CREATE TABLE secrets (value TEXT NOT NULL)')
        ..execute('INSERT INTO secrets (value) VALUES (?)', [_secret])
        ..close();

      final again = sqlite.sqlite3.open(file.path);
      addTearDown(again.close);
      _unlock(again, _key);

      expect(
        again.select('SELECT value FROM secrets').single['value'],
        equals(_secret),
      );
    });

    test('refuses a key that is not the one the database was written with', () {
      final file = aDatabaseFile();
      sqlite.sqlite3.open(file.path)
        ..let(_unlock, _key)
        ..execute('CREATE TABLE secrets (value TEXT NOT NULL)')
        ..close();

      final wrong = sqlite.sqlite3.open(file.path);
      addTearDown(wrong.close);
      _unlock(wrong, _otherKey);

      expect(
        () => wrong.select('SELECT * FROM secrets'),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('changes the key of a database in place', () {
      final file = aDatabaseFile();
      final database = sqlite.sqlite3.open(file.path);
      _unlock(database, _key);
      database
        ..execute('CREATE TABLE secrets (value TEXT NOT NULL)')
        ..execute('INSERT INTO secrets (value) VALUES (?)', [_secret])
        ..execute('PRAGMA rekey = "x\'$_otherKey\'"')
        ..close();

      final again = sqlite.sqlite3.open(file.path);
      addTearDown(again.close);
      _unlock(again, _otherKey);

      expect(
        again.select('SELECT value FROM secrets').single['value'],
        equals(_secret),
      );
    });
  });

  group('drift over the encrypted database', () {
    test(
      'opens the file with the key and keeps nothing readable on disk',
      () async {
        final file = aDatabaseFile();
        final executor = NativeDatabase(
          file,
          setup: (database) => _unlock(database, _key),
        );
        addTearDown(executor.close);
        await executor.ensureOpen(_NoUser());

        await executor.runCustom('CREATE TABLE secrets (value TEXT NOT NULL)');
        await executor.runInsert('INSERT INTO secrets (value) VALUES (?)', [
          _secret,
        ]);
        final rows = await executor.runSelect('SELECT value FROM secrets', []);

        expect(rows.single['value'], equals(_secret));
        await executor.close();
        expect(
          String.fromCharCodes(file.readAsBytesSync()),
          isNot(contains(_secret)),
        );
      },
    );

    test('works on a database in memory, which takes no key', () async {
      final executor = NativeDatabase.memory();
      addTearDown(executor.close);
      await executor.ensureOpen(_NoUser());

      await executor.runCustom('CREATE TABLE t (n INTEGER NOT NULL)');
      await executor.runInsert('INSERT INTO t (n) VALUES (?)', [7]);

      expect(
        (await executor.runSelect('SELECT n FROM t', [])).single['n'],
        equals(7),
      );
    });

    test(
      'refuses a key for a database in memory: the unlock is for files only',
      () async {
        final executor = NativeDatabase.memory(
          setup: (database) => _unlock(database, _key),
        );
        addTearDown(executor.close);

        await expectLater(
          executor.ensureOpen(_NoUser()),
          throwsA(isA<sqlite.SqliteException>()),
        );
      },
    );
  });
}

extension on sqlite.Database {
  void let(void Function(sqlite.Database, String) action, String argument) =>
      action(this, argument);
}

final class _NoUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
