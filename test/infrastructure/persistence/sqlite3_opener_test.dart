import 'dart:io';

import 'package:boardroom/infrastructure/persistence/boardroom_database.dart';
import 'package:boardroom/infrastructure/persistence/sqlite3_opener.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';

import '../support/test_files.dart';

// The device side of the database: `sqlite3` with SQLite3MultipleCiphers, and
// drift over the connection it opened. It is thin on purpose, so what is left
// to check is the conversation with the engine. What to do with a key, with a
// file that does not unlock and with a file in the way is tested in
// `unlock_database_test.dart` and `protected_database_test.dart`. React Native
// tests the same layer (`ExpoSqliteOpener`) against a stand-in for the native
// module; here the engine is real.

const String _name = 'boardroom.db';

void main() {
  final parent = temporaryDirectory();

  ({Directory directory, Sqlite3Opener opener}) anOpener() {
    final directory = Directory('${freshDirectory(parent).path}/databases');
    return (directory: directory, opener: Sqlite3Opener(directory));
  }

  group('Sqlite3Opener', () {
    test(
      'opens the file by its name and sends no statement of its own',
      () async {
        final (:directory, :opener) = anOpener();

        final connection = await opener.open(_name);

        expect(File('${directory.path}/$_name').existsSync(), isTrue);
        // Nothing was written: the file is made when the first statement needs
        // it, and the engine has not been given one.
        expect(File('${directory.path}/$_name').lengthSync(), equals(0));
        await connection.close();
      },
    );

    test('makes the folder of the databases when it opens the first', () async {
      final (:directory, :opener) = anOpener();
      expect(directory.existsSync(), isFalse);

      await (await opener.open(_name)).close();

      expect(directory.existsSync(), isTrue);
    });

    test('gives a connection that runs statements and reads rows', () async {
      final (directory: _, :opener) = anOpener();
      final connection = await opener.open(_name);

      await connection.exec('CREATE TABLE t (a TEXT, b INTEGER)');
      await connection.exec("INSERT INTO t VALUES ('x', 7)");
      final rows = await connection.all('SELECT a, b FROM t');

      expect(rows, [
        {'a': 'x', 'b': 7},
      ]);
      await connection.close();
    });

    test('gives rows that the engine does not change afterwards', () async {
      final (directory: _, :opener) = anOpener();
      final connection = await opener.open(_name);
      await connection.exec('CREATE TABLE t (a TEXT)');
      await connection.exec("INSERT INTO t VALUES ('x')");

      final rows = await connection.all('SELECT a FROM t');
      await connection.exec("UPDATE t SET a = 'y'");

      expect(rows, [
        {'a': 'x'},
      ]);
      await connection.close();
    });

    test('lets what the module says go, '
        'for the caller to turn into a result', () async {
      final (directory: _, :opener) = anOpener();
      final connection = await opener.open(_name);

      await expectLater(
        connection.exec('INSERT INTO nowhere VALUES (1)'),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        connection.all('SELECT * FROM nowhere'),
        throwsA(isA<SqliteException>()),
      );
      await connection.close();
    });

    test('closes the connection, and closing it again succeeds', () async {
      final (directory: _, :opener) = anOpener();
      final connection = await opener.open(_name);

      await connection.close();

      await expectLater(connection.close(), completes);
      await expectLater(connection.exec('SELECT 1'), throwsA(anything));
    });

    test('hands the connection over to drift, whose close closes it', () async {
      final (directory: _, :opener) = anOpener();
      final connection = await opener.open(_name);
      final database = BoardroomDatabase(connection.toExecutor());

      // The first statement opens the file and runs the migrations.
      final selected = await database.customSelect('SELECT 1 AS one').get();
      await database.close();

      expect(selected.single.data, equals({'one': 1}));
      await expectLater(connection.exec('SELECT 1'), throwsA(anything));
    });

    group('removing a database', () {
      test('deletes the file of a database that is closed', () async {
        final (:directory, :opener) = anOpener();
        final connection = await opener.open(_name);
        await connection.exec('CREATE TABLE t (a TEXT)');
        await connection.close();

        await opener.remove(_name);

        expect(File('${directory.path}/$_name').existsSync(), isFalse);
      });

      test('succeeds for a database that is not there, '
          'which the module rejects', () async {
        final (directory: _, :opener) = anOpener();

        await expectLater(opener.remove(_name), completes);
      });

      test('deletes the main file only, and no other file '
          'of the folder', () async {
        final (:directory, :opener) = anOpener();
        final connection = await opener.open(_name);
        await connection.exec('CREATE TABLE t (a TEXT)');
        await connection.close();
        File('${directory.path}/$_name-journal').writeAsStringSync('journal');
        File('${directory.path}/$_name.1').writeAsStringSync('next');

        await opener.remove(_name);

        expect(File('${directory.path}/$_name').existsSync(), isFalse);
        expect(File('${directory.path}/$_name-journal').existsSync(), isTrue);
        expect(File('${directory.path}/$_name.1').existsSync(), isTrue);
      });
    });
  });

  group('createDeviceDatabaseOpener', () {
    test('keeps the databases in a folder of the private storage '
        'of the app', () async {
      final storage = freshDirectory(parent);

      final opener = await createDeviceDatabaseOpener(
        locate: () async => storage,
      );
      await (await opener.open(_name)).close();

      expect(
        File('${storage.path}/$databaseDirectoryName/$_name').existsSync(),
        isTrue,
      );
      expect(opener, isA<Sqlite3Opener>());
    });
  });
}
