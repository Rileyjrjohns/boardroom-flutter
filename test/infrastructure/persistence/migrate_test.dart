import 'dart:io';

import 'package:boardroom/infrastructure/persistence/boardroom_database.dart';
import 'package:boardroom/infrastructure/persistence/migrate.dart';
import 'package:boardroom/infrastructure/persistence/migrations.dart' as schema;
import 'package:boardroom/infrastructure/persistence/schema.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../support/test_database.dart';

// Brings the schema to the last of the migrations. In React Native the
// migrations are run by a function on an open connection; here drift runs them
// when it opens the database (`migrationStrategyOf`), so a test opens the file
// with the migrations of an older version of the app, closes it, and opens it
// again with the migrations it wants to test. The outcome of the run (the
// version and how many migrations ran) has no Dart counterpart: the tests look
// at the `user_version` of the file instead.

const String _version = 'PRAGMA user_version';
const String _objects =
    "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'";

Future<int> _versionOf(BoardroomDatabase database) async =>
    (await database.all(_version)).single['user_version']! as int;

Future<List<String>> _objectsOf(BoardroomDatabase database) async =>
    [for (final row in await database.all(_objects)) '${row['name']}']..sort();

/// What a file holds, read without drift, so that nothing runs on it.
({int version, List<String> objects}) _contentOf(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    return (
      version: database.select(_version).single['user_version']! as int,
      objects: [for (final row in database.select(_objects)) '${row['name']}']
        ..sort(),
    );
  } finally {
    database.close();
  }
}

/// Rows that are valid at the version, written the way that version wrote
/// them.
Future<void> _fillAtVersion(BoardroomDatabase database) async {
  await database.run(
    'INSERT INTO ${StoredTable.meetingDetails.value} '
    '(owner, meeting_id, cached_at, payload) VALUES (?, ?, ?, ?)',
    ['owner', 'meeting', 1, '{}'],
  );
  await database.run(
    'INSERT INTO ${StoredTable.outboxVotes.value} '
    '(idempotency_key, voter_id, resolution_id, meeting_id, choice, cast_at, '
    'enqueued_at, attempts, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    ['key', 'voter', 'resolution', 'meeting', 'for', 1, 2, 3, 'pending'],
  );
}

/// A file that nothing was ever written to: no version, no table.
void _expectUntouched(File file) {
  final content = _contentOf(file);
  expect(content.version, equals(0));
  expect(content.objects, isEmpty);
}

Matcher _failureOf(MigrationFailureKind kind, [int? version]) =>
    isA<MigrationFailure>()
        .having((failure) => failure.kind, 'kind', kind)
        .having((failure) => failure.version, 'version', version);

void main() {
  final directory = databaseDirectory();
  final latest = schema.migrations.last.version;

  group('MigrationFailure', () {
    test('compares by its kind, its version and its cause, '
        'and prints no statement', () {
      const failure = MigrationFailure(
        kind: MigrationFailureKind.migrationFailed,
        version: 3,
        cause: 'sqlite error 1',
      );

      expect(
        failure,
        equals(
          const MigrationFailure(
            kind: MigrationFailureKind.migrationFailed,
            version: 3,
            cause: 'sqlite error 1',
          ),
        ),
      );
      expect(
        failure.hashCode,
        equals(
          const MigrationFailure(
            kind: MigrationFailureKind.migrationFailed,
            version: 3,
            cause: 'sqlite error 1',
          ).hashCode,
        ),
      );
      expect(
        failure,
        isNot(
          equals(
            const MigrationFailure(
              kind: MigrationFailureKind.migrationFailed,
              version: 4,
              cause: 'sqlite error 1',
            ),
          ),
        ),
      );
      expect(
        '$failure',
        equals('MigrationFailure(migrationFailed, 3, sqlite error 1)'),
      );
    });
  });

  group('the migrations', () {
    test('are numbered 1, 2, 3, ... with no gap', () {
      expect(schema.migrations.map((migration) => migration.version), [
        for (var position = 0; position < schema.migrations.length; position++)
          position + 1,
      ]);
      expect(migrationsAreInOrder(schema.migrations), isTrue);
    });

    test(
      'create the caches and the outbox, and the indexes, in a new database',
      () async {
        final test = await openTestDatabase(directory);

        expect(await _versionOf(test.database), equals(latest));
        expect(
          await _objectsOf(test.database),
          equals(
            [
              StoredTable.meetingPages.value,
              StoredTable.meetingDetails.value,
              StoredTable.documentEntries.value,
              StoredTable.outboxVotes.value,
              StoredIndex.outboxByResolution.value,
              StoredIndex.documentEntriesByLocation.value,
            ]..sort(),
          ),
        );
      },
    );

    for (final past in schema.migrations.map(
      (migration) => migration.version,
    )) {
      test('bring a database that is at version $past to the latest, '
          'with its content', () async {
        final old = await openTestDatabase(
          directory,
          schema.migrations.sublist(0, past),
        );
        await _fillAtVersion(old.database);
        expect(await _versionOf(old.database), equals(past));

        final test = await old.reopen(schema.migrations);

        expect(await _versionOf(test.database), equals(latest));
        final keys = await test.database.all(
          'SELECT idempotency_key FROM ${StoredTable.outboxVotes.value}',
        );
        expect([for (final row in keys) row['idempotency_key']], ['key']);
        expect(
          await test.database.all(
            'SELECT meeting_id FROM ${StoredTable.meetingDetails.value}',
          ),
          hasLength(1),
        );
        expect(
          await _objectsOf(test.database),
          contains(StoredIndex.outboxByResolution.value),
        );
        // Version 4 added the cache of documents, empty whatever the version
        // it came from.
        expect(
          await test.database.all(
            'SELECT * FROM ${StoredTable.documentEntries.value}',
          ),
          isEmpty,
        );
      });
    }

    test('make the cache of documents refuse two entries '
        'for the same owner and document', () async {
      final test = await openTestDatabase(directory);
      final database = test.database;
      final insert =
          'INSERT INTO ${StoredTable.documentEntries.value} '
          '(owner, document_id, cached_at, location, payload) '
          'VALUES (?, ?, ?, ?, ?)';
      await database.run(insert, [
        'owner',
        'document',
        1,
        'file:///a.pdf',
        '{}',
      ]);

      await expectLater(
        database.run(insert, ['owner', 'document', 2, 'file:///b.pdf', '{}']),
        throwsA(isA<sqlite.SqliteException>()),
      );
      // Another owner, or another document, is another entry.
      await database.run(insert, [
        'other',
        'document',
        1,
        'file:///a.pdf',
        '{}',
      ]);
      await database.run(insert, ['owner', 'other', 1, 'file:///a.pdf', '{}']);
      expect(
        await database.all(
          'SELECT * FROM ${StoredTable.documentEntries.value}',
        ),
        hasLength(3),
      );
    });

    test('do nothing to a database that is up to date', () async {
      final first = await openTestDatabase(directory);
      await _fillAtVersion(first.database);

      final test = await first.reopen();

      expect(await _versionOf(test.database), equals(latest));
      expect(
        await test.database.all(
          'SELECT * FROM ${StoredTable.outboxVotes.value}',
        ),
        hasLength(1),
      );
    });

    test('run again from where they stopped '
        'when the app was stopped between two of them', () async {
      final stopped = await openTestDatabase(
        directory,
        schema.migrations.sublist(0, 1),
      );

      final test = await stopped.reopen(schema.migrations);

      expect(await _versionOf(test.database), equals(latest));
    });

    group('a migration that fails', () {
      const third = schema.Migration(
        version: 5,
        statements: [
          'CREATE TABLE half_done (id INTEGER)',
          'INSERT INTO half_done VALUES (1)',
          'INSERT INTO a_table_that_is_not_there VALUES (1)',
        ],
      );
      final withThird = [...schema.migrations, third];

      test('leaves the database at the version before it, '
          'with nothing of what it had begun', () async {
        final current = await openTestDatabase(directory);
        await _fillAtVersion(current.database);
        final before = await _objectsOf(current.database);
        await current.database.close();

        await expectLater(
          openTestFile(current.file!, withThird),
          throwsA(_failureOf(MigrationFailureKind.migrationFailed, 5)),
        );

        final left = _contentOf(current.file!);
        expect(left.version, equals(latest));
        expect(left.objects, equals(before));
        final test = await openTestFile(current.file!);
        expect(
          await test.database.all(
            'SELECT * FROM ${StoredTable.outboxVotes.value}',
          ),
          hasLength(1),
        );
      });

      test('keeps the migrations that succeeded before it', () async {
        final file = File('${directory.path}/succeeded-before.db');

        await expectLater(
          openTestFile(file, withThird),
          throwsA(_failureOf(MigrationFailureKind.migrationFailed, 5)),
        );

        expect(_contentOf(file).version, equals(latest));
      });

      test('does not put the text of the statement '
          'or of the engine in its cause', () async {
        final file = File('${directory.path}/no-text.db');

        Object? failure;
        try {
          await openTestFile(file, withThird);
        } on Object catch (error) {
          failure = error;
        }

        expect(failure, isA<MigrationFailure>());
        expect('$failure', isNot(contains('a_table_that_is_not_there')));
        expect((failure! as MigrationFailure).cause, equals('sqlite error 1'));
      });

      test('can be run again once it is fixed', () async {
        final file = File('${directory.path}/fixed-later.db');
        await expectLater(
          openTestFile(file, withThird),
          throwsA(isA<MigrationFailure>()),
        );
        const fixed = schema.Migration(
          version: 5,
          statements: ['CREATE TABLE fixed (id INTEGER)'],
        );

        final test = await openTestFile(file, [...schema.migrations, fixed]);

        expect(await _versionOf(test.database), equals(5));
        expect(await _objectsOf(test.database), contains('fixed'));
      });
    });

    test('refuse a database that a more recent version of the app wrote, '
        'and leave it alone', () async {
      final current = await openTestDatabase(directory);
      await current.database.run('PRAGMA user_version = ${latest + 5}');
      await current.database.close();
      final before = _contentOf(current.file!);

      await expectLater(
        openTestFile(current.file!),
        throwsA(_failureOf(MigrationFailureKind.databaseIsNewer, latest + 5)),
      );

      final after = _contentOf(current.file!);
      expect(after.version, equals(latest + 5));
      expect(after.objects, equals(before.objects));
    });

    final invalidLists = <(String, List<schema.Migration>)>[
      (
        'a gap',
        [
          const schema.Migration(version: 1, statements: []),
          const schema.Migration(version: 3, statements: []),
        ],
      ),
      (
        'a list that does not start at 1',
        [const schema.Migration(version: 2, statements: [])],
      ),
      (
        'a repeated version',
        [
          const schema.Migration(version: 1, statements: []),
          const schema.Migration(version: 1, statements: []),
        ],
      ),
    ];
    for (final (name, list) in invalidLists) {
      test(
        'refuse $name in the list of migrations, before touching the database',
        () async {
          final file = File('${directory.path}/invalid-$name.db');
          expect(migrationsAreInOrder(list), isFalse);

          await expectLater(
            openTestFile(file, list),
            throwsA(_failureOf(MigrationFailureKind.invalidMigrations)),
          );

          _expectUntouched(file);
        },
      );
    }

    test('refuse an empty list of migrations: drift has no database '
        'without a version', () async {
      final file = File('${directory.path}/empty-list.db');
      expect(migrationsAreInOrder(const []), isFalse);

      await expectLater(
        openTestFile(file, const []),
        throwsA(_failureOf(MigrationFailureKind.invalidMigrations)),
      );

      _expectUntouched(file);
    });
  });
}
