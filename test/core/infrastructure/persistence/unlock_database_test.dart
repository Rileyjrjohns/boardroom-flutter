import 'dart:io';

import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/persistence/database_opener.dart';
import 'package:boardroom/core/infrastructure/persistence/sqlite3_opener.dart';
import 'package:boardroom/core/infrastructure/persistence/unlock_database.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';

import '../../../support/builders/names.dart';
import '../../../support/infrastructure/test_files.dart';

final String _key = 'a' * 64;
final String _otherKey = 'b' * 64;

/// What the connection of a file says to the statements of the unlock: the
/// engine of the device is SQLite3MultipleCiphers, so the tests of the real
/// thing use real files (React Native simulated the answers of SQLCipher).
const String _readSchema = 'SELECT count(*) FROM sqlite_master';

/// A connection that records what it is sent and answers what the test
/// scripted.
final class _Scripted implements EngineConnection {
  new({
    this.cipherRows = const [
      {'cipher': 'sqlcipher'},
    ],
    this.readFails,
    this.execFails,
    this.closeFails = false,
  });

  final List<Map<String, Object?>> cipherRows;
  final Object? readFails;
  final Object? execFails;
  final bool closeFails;

  final List<String> statements = [];
  int closed = 0;

  @override
  Future<void> exec(String sql) {
    statements.add(sql);
    final failure = execFails;
    return failure == null ? Future.value() : Future.error(failure);
  }

  @override
  Future<List<Map<String, Object?>>> all(String sql) {
    statements.add(sql);
    if (sql == cipherProbe) {
      return Future.value(cipherRows);
    }
    final failure = readFails;
    return failure == null ? Future.value([]) : Future.error(failure);
  }

  @override
  Future<void> close() {
    closed += 1;
    return closeFails ? Future.error(StateError('stuck')) : Future.value();
  }

  @override
  QueryExecutor toExecutor() => throw UnimplementedError();
}

void main() {
  final parent = temporaryDirectory();

  /// A file of the machine, on the engine of the device.
  ({DatabaseOpener opener, String name}) aFile() => (
    opener: Sqlite3Opener(Directory('${freshDirectory(parent).path}/files')),
    name: 'unlock.db',
  );

  group('unlockDatabase', () {
    test('unlocks with the key as a raw key, checks it is SQLCipher, '
        'and reads the file', () async {
      final scripted = _Scripted();

      final unlocked = await unlockDatabase(scripted, _key);

      expect(unlocked, equals(ok<void>(null)));
      expect(
        scripted.statements,
        equals([
          selectCipher,
          'PRAGMA key = "x\'$_key\'"',
          cipherProbe,
          _readSchema,
        ]),
      );
      expect(scripted.closed, equals(0));
    });

    test('opens a file again with the key it was created with', () async {
      final (:opener, :name) = aFile();
      final created = await opener.open(name);
      await unlockDatabase(created, _key);
      // The key binds the file when something is written to it.
      await created.exec('CREATE TABLE secrets (value TEXT)');
      await created.close();

      final again = await unlockDatabase(await opener.open(name), _key);

      expect(again, isA<Ok<void, UnlockFailure>>());
    });

    test('says the key is rejected when the file was created with another key, '
        'and closes the connection', () async {
      final (:opener, :name) = aFile();
      final created = await opener.open(name);
      await unlockDatabase(created, _key);
      await created.exec('CREATE TABLE secrets (value TEXT)');
      await created.close();
      final other = _Scripted(readFails: Exception('file is not a database'));
      final connection = await opener.open(name);

      final rejected = await unlockDatabase(connection, _otherKey);
      final scriptedRejected = await unlockDatabase(other, _key);

      expect(rejected, equals(err(UnlockFailure.keyRejected)));
      expect(scriptedRejected, equals(err(UnlockFailure.keyRejected)));
      expect(other.closed, equals(1));
      // The connection of the real file was closed too: closing it again does
      // not fail, and it holds no lock on the file.
      await connection.close();
    });

    final notADatabase = <(String, Object)>[
      ('the message in other letters', Exception('NOT A DATABASE')),
      (
        'the message with words around it',
        Exception('sqlite3: file is not a database (26)'),
      ),
      (
        'the result code, from an engine that gives one',
        SqliteException(extendedResultCode: 26, message: 'x'),
      ),
    ];
    for (final (name, failure) in notADatabase) {
      test('recognises a file that is not a database by $name', () async {
        final scripted = _Scripted(readFails: failure);

        expect(
          await unlockDatabase(scripted, _key),
          equals(err(UnlockFailure.keyRejected)),
        );
      });
    }

    final otherFailures = <(String, Object)>[
      ('a failure with another message', Exception('disk I/O error')),
      (
        'a failure with another code',
        SqliteException(extendedResultCode: 5, message: 'busy'),
      ),
      ('something that is not an error', 'oops'),
    ];
    for (final (name, failure) in otherFailures) {
      test('says it failed, not that the key is rejected, for $name', () async {
        final scripted = _Scripted(readFails: failure);
        final thrown = _Scripted(execFails: failure);

        expect(
          await unlockDatabase(scripted, _key),
          equals(err(UnlockFailure.failed)),
        );
        expect(
          await unlockDatabase(thrown, _key),
          equals(err(UnlockFailure.failed)),
        );
        expect(scripted.closed, equals(1));
        expect(thrown.closed, equals(1));
      });
    }

    test('refuses to store anything when the engine is plain SQLite, '
        'which would ignore the key', () async {
      final scripted = _Scripted(cipherRows: const []);

      expect(
        await unlockDatabase(scripted, _key),
        equals(err(UnlockFailure.encryptionUnavailable)),
      );
      expect(scripted.statements, isNot(contains(_readSchema)));
      expect(scripted.closed, equals(1));
    });

    test('survives a connection that does not close', () async {
      final scripted = _Scripted(
        readFails: Exception('file is not a database'),
        closeFails: true,
      );

      expect(
        await unlockDatabase(scripted, _key),
        equals(err(UnlockFailure.keyRejected)),
      );
    });

    final badKeys = <String>[
      '',
      'short',
      'g' * 64,
      '${_key}0',
      '"; DROP TABLE x; --'.padRight(64, 'a'),
      _key.toUpperCase(),
    ];
    for (final key in badKeys) {
      test('refuses a key that is not 64 lower case hexadecimal digits, '
          'before it reaches a statement: ${formatJson(key)}', () async {
        final scripted = _Scripted();

        expect(
          await unlockDatabase(scripted, key),
          equals(err(UnlockFailure.failed)),
        );
        expect(scripted.statements, isEmpty);
        expect(scripted.closed, equals(1));
      });
    }

    test(
      'reads a file of the device engine back with the key it was written with',
      () async {
        final (:opener, :name) = aFile();
        final created = await opener.open(name);
        await unlockDatabase(created, _key);
        await created.exec('CREATE TABLE secrets (value TEXT)');
        await created.exec("INSERT INTO secrets (value) VALUES ('kept')");
        await created.close();

        final again = await opener.open(name);
        await unlockDatabase(again, _key);

        expect(
          await again.all('SELECT value FROM secrets'),
          equals([
            {'value': 'kept'},
          ]),
        );
        await again.close();
      },
    );
  });
}
