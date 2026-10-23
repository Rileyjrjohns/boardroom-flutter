import 'package:drift/drift.dart';

// The table of the votes as drift knows it: the names and the types of the
// columns, for the queries that write to them. The database itself is
// created by the migrations (`lib/app/persistence/migrations.dart`), which are
// the format of the file, so a test checks that these declarations and the
// migrations describe the same columns. The constraints are the migrations'
// alone: the file is never created from these declarations.
//
// Drift derives the name of a table and of a column from the Dart name
// (`idempotencyKey` is `idempotency_key`, `OutboxVotes` is `outbox_votes`), and
// the generator needs them as literals, so the names of `schema.dart`, which
// are the ones written in the file, are not repeated here: the same test checks
// that the two agree.

/// The votes of the outbox, in the order they were enqueued.
@DataClassName('OutboxVoteRow')
class OutboxVotes extends Table {
  /// The order of enqueueing, which only grows.
  IntColumn get sequence => integer().autoIncrement()();

  /// The key the vote is found by.
  TextColumn get idempotencyKey => text().unique()();

  /// Who voted.
  TextColumn get voterId => text()();

  /// The resolution voted on.
  TextColumn get resolutionId => text()();

  /// The meeting of the resolution.
  TextColumn get meetingId => text()();

  /// What the voter answered.
  TextColumn get choice => text()();

  /// When the vote was cast.
  IntColumn get castAt => integer()();

  /// When the vote was queued.
  IntColumn get enqueuedAt => integer()();

  /// How many times sending the vote failed.
  IntColumn get attempts => integer()();

  /// Pending, rejected, or quarantined.
  TextColumn get status => text()();

  /// Why the vote was rejected, as JSON.
  TextColumn get rejectionReason => text().nullable()();

  /// When the vote was rejected.
  IntColumn get rejectedAt => integer().nullable()();
}
