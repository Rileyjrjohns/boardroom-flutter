import 'package:boardroom/app/persistence/migrations.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/infrastructure/persistence/guarded.dart';
import 'package:boardroom/core/infrastructure/shared/attempt.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

// Brings the schema to the last of the migrations. Drift keeps the version of
// the schema in the `user_version` of the header of the database and calls the
// strategy below when it opens the file: `onCreate` for a file that has no
// version yet, `onUpgrade` for a file that has another one. Each migration runs
// in its own transaction together with the update of that version, so a
// failure leaves the database at the version before it, which the next start
// retries from. A database that is already there does nothing, and one that is
// more recent than the migrations is refused.

/// Why the schema could not be brought up to date.
enum MigrationFailureKind implements StableValue {
  /// The list of migrations is not 1, 2, 3, ...: a bug of the app, found by its
  /// tests.
  invalidMigrations('invalidMigrations'),

  /// The database was written by a more recent version of the app. It is left
  /// alone.
  databaseIsNewer('databaseIsNewer'),

  /// A migration failed. It was rolled back: the database is at the version
  /// before it.
  migrationFailed('migrationFailed');

  new(this.value);

  @override
  final String value;
}

/// What the strategy throws, for drift to report that the database could not
/// be opened. The caller of `openProtectedDatabase` never sees it: it is turned
/// into a result.
@immutable
final class MigrationFailure implements Exception {
  /// Creates the failure of the given [kind].
  const new({required this.kind, this.version, this.cause});

  /// What went wrong.
  final MigrationFailureKind kind;

  /// The version of the migration that failed, or the one the database is at.
  final int? version;

  /// A kind of failure, never a statement nor a message of the engine.
  final String? cause;

  @override
  bool operator ==(Object other) =>
      other is MigrationFailure &&
      other.kind == kind &&
      other.version == version &&
      other.cause == cause;

  @override
  int get hashCode => Object.hash(kind, version, cause);

  @override
  String toString() => 'MigrationFailure(${kind.value}, $version, $cause)';
}

/// Where the version of the schema is kept, once a migration has run: the
/// `user_version` of the header of the database.
const String _writeVersion = 'PRAGMA user_version';

/// Whether the versions are 1, 2, 3, ... with no gap. A list with no migration
/// is not one: drift refuses a schema with no version.
bool migrationsAreInOrder(List<Migration> migrations) =>
    migrations.isNotEmpty &&
    migrations.indexed.every((entry) => entry.$2.version == entry.$1 + 1);

/// The strategy that creates the schema from nothing, or brings it to the last
/// of [migrations]. It throws a [MigrationFailure] when it cannot.
MigrationStrategy migrationStrategyOf(List<Migration> migrations) {
  Future<void> bringUpTo(GeneratedDatabase database, int from) async {
    for (final migration in migrations.where((step) => step.version > from)) {
      try {
        await database.transaction(() async {
          for (final statement in migration.statements) {
            await database.customStatement(statement);
          }
          // A version is a whole number of our own list, so it can be written
          // into the statement: `PRAGMA` takes no parameter.
          await database.customStatement(
            '$_writeVersion = ${migration.version}',
          );
        });
      } on Object catch (error) {
        throw MigrationFailure(
          kind: MigrationFailureKind.migrationFailed,
          version: migration.version,
          cause: describeFailure(engineFailureOf(error)),
        );
      }
    }
  }

  // A list that is not 1, 2, 3, ... is refused before the database is touched.
  void requireInOrder() {
    if (!migrationsAreInOrder(migrations)) {
      throw const MigrationFailure(
        kind: MigrationFailureKind.invalidMigrations,
      );
    }
  }

  return MigrationStrategy(
    onCreate: (migrator) {
      requireInOrder();
      return bringUpTo(migrator.database, 0);
    },
    onUpgrade: (migrator, from, to) {
      requireInOrder();
      if (from > to) {
        // Drift calls `onUpgrade` for a database that has a version other than
        // its own, a more recent one included. It is refused, not touched.
        throw MigrationFailure(
          kind: MigrationFailureKind.databaseIsNewer,
          version: from,
        );
      }
      return bringUpTo(migrator.database, from);
    },
  );
}
