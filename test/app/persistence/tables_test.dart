import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/features/documents/infrastructure/persistence/schema.dart';
import 'package:boardroom/features/meetings/infrastructure/persistence/schema.dart';
import 'package:boardroom/features/votes/infrastructure/persistence/schema.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../../support/infrastructure/test_database.dart';

// The tables of drift (the `tables.dart` of each feature) are the names and the
// types of the columns the queries write to; the file is created by the
// migrations (`migrations.dart`). Nothing but these tests makes sure the two
// describe the same tables, and that the names drift derives from the Dart
// names are the ones written in the file (the `schema.dart` of each feature).
// They have no React Native counterpart: there the queries are text.

/// The type SQLite declares for a column of this type.
String _declaredType(Object type) {
  if (type == DriftSqlType.string) {
    return 'TEXT';
  }
  if (type == DriftSqlType.int) {
    return 'INTEGER';
  }
  throw ArgumentError('A column of $type is not used by the schema.');
}

void main() {
  group('the tables of drift', () {
    test('are the tables the migrations create', () async {
      final test = await openTestDatabase();

      final created = await test.database.all(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      );

      expect({
        for (final table in test.database.allTables) table.actualTableName,
      }, equals({for (final row in created) row['name']}));
    });

    test('have the names of the schema', () async {
      final test = await openTestDatabase();

      expect(
        {for (final table in test.database.allTables) table.actualTableName},
        equals({
          MeetingStoredTable.meetingPages.value,
          MeetingStoredTable.meetingDetails.value,
          DocumentStoredTable.documentEntries.value,
          VoteStoredTable.outboxVotes.value,
        }),
      );
    });

    test('have the columns of the migrations, '
        'with their types and their nullability', () async {
      final test = await openTestDatabase();

      for (final table in test.database.allTables) {
        final declared = await test.database.all(
          'PRAGMA table_info(${table.actualTableName})',
        );
        expect(
          {
            for (final column in table.$columns)
              column.name: (
                _declaredType(column.type),
                !column.$nullable,
                table.$primaryKey.contains(column),
              ),
          },
          equals({
            for (final row in declared)
              '${row['name']}': (
                '${row['type']}',
                row['notnull'] == 1 || row['pk'] != 0,
                row['pk'] != 0,
              ),
          }),
          reason: table.actualTableName,
        );
      }
    });

    test('have columns the schema names', () async {
      final test = await openTestDatabase();
      final names = {
        ...valuesOf(MeetingStoredColumn.values),
        ...valuesOf(DocumentStoredColumn.values),
        ...valuesOf(VoteStoredColumn.values),
      };

      for (final table in test.database.allTables) {
        expect(
          {for (final column in table.$columns) column.name},
          everyElement(isIn(names)),
          reason: table.actualTableName,
        );
      }
      // Every column of the schema is used by a table.
      expect({
        for (final table in test.database.allTables)
          for (final column in table.$columns) column.name,
      }, equals(names));
    });
  });
}
