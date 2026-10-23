import 'package:boardroom/app/persistence/boardroom_database.drift.dart';
import 'package:boardroom/app/persistence/migrations.dart' as schema;
import 'package:boardroom/core/infrastructure/persistence/migrate.dart';
import 'package:boardroom/features/documents/infrastructure/persistence/tables.dart';
import 'package:boardroom/features/meetings/infrastructure/persistence/tables.dart';
import 'package:boardroom/features/votes/infrastructure/persistence/tables.dart';
import 'package:drift/drift.dart';

/// The local database of the whole app: the offline cache of meetings and
/// documents and the outbox of votes. It is opened by `openProtectedDatabase`,
/// over a file that is encrypted, and by the tests, over a file or over the
/// memory.
///
/// It holds no table of its own. Each feature declares the tables it owns, and
/// reads and writes them through its own adapter (a `DriftMeetingCache`, a
/// `DriftDocumentCache`, a `DriftVoteOutbox` over a `GeneratedDatabase`); this
/// class lists them, so that one file holds them all, and it brings the schema
/// of the file to the last of the migrations of the app (`migrations.dart`).
@DriftDatabase(
  tables: [MeetingPages, MeetingDetails, DocumentEntries, OutboxVotes],
)
class BoardroomDatabase extends $BoardroomDatabase {
  /// Creates the database over the executor [e]. Its schema is brought to the
  /// last of [migrations] (all of the app's by default) when the executor is
  /// first used.
  new(super.e, {List<Migration>? migrations})
    : _migrations = migrations ?? schema.migrations;

  final List<Migration> _migrations;

  // Drift refuses a schema with no version, so a list with no migration opens
  // as version 1, and `migrationStrategyOf` refuses it.
  @override
  int get schemaVersion => _migrations.isEmpty ? 1 : _migrations.last.version;

  @override
  MigrationStrategy get migration => migrationStrategyOf(_migrations);
}

/// Makes the database of the app over a connection, the way
/// `openProtectedDatabase` asks for it.
BoardroomDatabase createBoardroomDatabase(
  QueryExecutor executor,
  List<Migration> migrations,
) => BoardroomDatabase(executor, migrations: migrations);
