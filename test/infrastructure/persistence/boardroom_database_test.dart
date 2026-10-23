import 'dart:async';

import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';

import '../support/database_faults.dart';
import '../support/test_database.dart';

// In React Native a small layer over the engine (`createSqlDatabase`) makes the
// statements run one at a time and gives the transactions; the adapters are
// written against it. Here drift is that layer, so these are the scenarios of
// its tests, run on `BoardroomDatabase`: what the adapters rely on is the same
// (a statement that binds its parameters, a transaction that commits or rolls
// back whole, statements that never land inside the transaction of another
// caller).

void main() {
  /// A database in memory with a table of its own.
  Future<TestDatabase> withTable() async {
    final test = await openTestDatabase();
    await test.database.run(
      'CREATE TABLE items (name TEXT NOT NULL, amount INTEGER)',
    );
    return test;
  }

  Future<List<Object?>> namesOf(TestDatabase test) async => [
    for (final row in await test.database.all('SELECT name FROM items'))
      row['name'],
  ];

  group('BoardroomDatabase', () {
    test('runs a statement with its parameters '
        'and reads the rows back by column name', () async {
      final test = await withTable();

      await test.database.run(
        'INSERT INTO items (name, amount) VALUES (?, ?)',
        ['a', 3],
      );
      await test.database.run(
        'INSERT INTO items (name, amount) VALUES (?, ?)',
        ['b', null],
      );
      final rows = await test.database.all(
        'SELECT name, amount FROM items WHERE name = ?',
        ['a'],
      );

      expect(rows, [
        {'name': 'a', 'amount': 3},
      ]);
    });

    test('binds a parameter as a value, '
        'never as part of the statement', () async {
      final test = await withTable();
      const hostile = "x'); DROP TABLE items; --";

      await test.database.run('INSERT INTO items (name) VALUES (?)', [hostile]);

      expect(await namesOf(test), equals([hostile]));
    });

    test('commits what a transaction did when its work resolves, '
        'and returns its value', () async {
      final test = await withTable();

      final value = await test.database.transaction(() async {
        await test.database.run('INSERT INTO items (name) VALUES (?)', ['a']);
        await test.database.run('INSERT INTO items (name) VALUES (?)', ['b']);
        return (await test.database.all('SELECT count(*) AS total FROM items'))
            .single['total'];
      });

      expect(value, equals(2));
      expect(await namesOf(test), hasLength(2));
    });

    test('rolls back everything a transaction did when its work rejects, '
        'and passes the rejection on', () async {
      final test = await withTable();
      await test.database.run('INSERT INTO items (name) VALUES (?)', ['kept']);

      final failed = test.database.transaction(() async {
        await test.database.run('DELETE FROM items');
        await test.database.run('INSERT INTO items (name) VALUES (?)', [
          'lost',
        ]);
        throw StateError('the work failed');
      });

      await expectLater(
        failed,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'the work failed',
          ),
        ),
      );
      expect(await namesOf(test), equals(['kept']));
    });

    test('rolls back and rejects when the commit itself fails', () async {
      final test = await withTable();

      final failed = test.database.transaction(() async {
        await test.database.run('INSERT INTO items (name) VALUES (?)', ['a']);
        test.faults.failNext();
      });

      await expectLater(failed, throwsA(isA<DatabaseFailure>()));
      expect(await namesOf(test), isEmpty);
      // The connection is not left in the middle of a transaction.
      await test.database.run('INSERT INTO items (name) VALUES (?)', ['b']);
      expect(await namesOf(test), hasLength(1));
    });

    test('does not start the work of a transaction '
        'that could not begin', () async {
      final test = await withTable();
      var started = false;
      test.faults.failNext();

      final failed = test.database.transaction(() async {
        started = true;
        await test.database.run('INSERT INTO items (name) VALUES (?)', ['a']);
      });

      await expectLater(failed, throwsA(isA<DatabaseFailure>()));
      expect(started, isFalse);
      expect(await namesOf(test), isEmpty);
    });

    test('runs statements one at a time '
        'in the order they were asked for', () async {
      final test = await withTable();

      await Future.wait([
        for (final number in [1, 2, 3, 4, 5])
          test.database.run('INSERT INTO items (name, amount) VALUES (?, ?)', [
            'n',
            number,
          ]),
      ]);

      final rows = await test.database.all(
        'SELECT amount FROM items ORDER BY rowid',
      );
      expect([for (final row in rows) row['amount']], [1, 2, 3, 4, 5]);
    });

    test('never lets a statement land inside the transaction '
        'of another caller', () async {
      final test = await withTable();

      final slow = test.database.transaction(() async {
        await test.database.run('INSERT INTO items (name) VALUES (?)', [
          'inside',
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // If the lone statement below had landed in this transaction, this
        // would see it.
        final seen = await test.database.all('SELECT name FROM items');
        throw StateError('rolled back after seeing ${seen.length} row');
      });
      final lone = test.database.run('INSERT INTO items (name) VALUES (?)', [
        'outside',
      ]);

      await expectLater(
        slow,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('after seeing 1 row'),
          ),
        ),
      );
      await lone;
      expect(await namesOf(test), equals(['outside']));
    });

    test('keeps working after a statement failed', () async {
      final test = await withTable();

      await expectLater(
        test.database.run('INSERT INTO nowhere VALUES (1)'),
        throwsA(isA<SqliteException>()),
      );
      await test.database.run('INSERT INTO items (name) VALUES (?)', ['a']);

      expect(await namesOf(test), hasLength(1));
    });

    test('closes the connection '
        'after the statements asked for before', () async {
      final test = await withTable();
      final inserting = test.database.run(
        'INSERT INTO items (name) VALUES (?)',
        ['a'],
      );

      await test.database.close();

      await expectLater(inserting, completes);
      await expectLater(test.database.all('SELECT 1'), throwsA(anything));
    });
  });

  group('the drift executor', () {
    test('is the one of a database in memory: nothing is kept '
        'after it is closed', () async {
      final first = await openTestDatabase();
      await first.database.run('CREATE TABLE kept (a TEXT)');
      await first.database.close();

      final second = await openTestDatabase();

      expect(
        await second.database.all(
          "SELECT name FROM sqlite_master WHERE name = 'kept'",
        ),
        isEmpty,
      );
    });

    test('fails every statement of a closed database', () async {
      final test = await openTestDatabase();
      await test.database.close();

      await expectLater(
        test.database.customSelect('SELECT 1').get(),
        throwsA(anything),
      );
    });
  });
}
