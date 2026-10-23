import 'package:boardroom/infrastructure/persistence/migrate.dart';
import 'package:boardroom/infrastructure/persistence/migrations.dart' as schema;
import 'package:boardroom/infrastructure/persistence/tables.dart';
import 'package:drift/drift.dart';

part 'boardroom_database.g.dart';

/// The local database of the app: the offline cache of meetings and documents
/// and the outbox of votes. It is opened by `openProtectedDatabase`, over a
/// file that is encrypted, and by the tests, over a file or over the memory.
@DriftDatabase(
  tables: [MeetingPages, MeetingDetails, DocumentEntries, OutboxVotes],
)
class BoardroomDatabase extends _$BoardroomDatabase {
  /// Creates the database over [executor]. Its schema is brought to the last of
  /// [migrations] (all of the app's by default) when the executor is first
  /// used.
  new(super.e, {List<schema.Migration>? migrations})
    : _migrations = migrations ?? schema.migrations;

  final List<schema.Migration> _migrations;

  // Drift refuses a schema with no version, so a list with no migration opens
  // as version 1, and `migrationStrategyOf` refuses it.
  @override
  int get schemaVersion => _migrations.isEmpty ? 1 : _migrations.last.version;

  @override
  MigrationStrategy get migration => migrationStrategyOf(_migrations);
}
