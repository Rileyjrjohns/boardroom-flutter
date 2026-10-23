import 'package:drift/drift.dart';

// The tables of the meetings as drift knows them: the names and the types of
// the columns, for the queries that write to them. The database itself is
// created by the migrations (`lib/app/persistence/migrations.dart`), which are
// the format of the file, so a test checks that these declarations and the
// migrations describe the same columns. The constraints are the migrations'
// alone: the file is never created from these declarations.
//
// Drift derives the name of a table and of a column from the Dart name
// (`cursorKey` is `cursor_key`, `MeetingPages` is `meeting_pages`), and the
// generator needs them as literals, so the names of `schema.dart`, which are
// the ones written in the file, are not repeated here: the same test checks
// that the two agree.

/// The pages of the list of meetings, one row for each owner, period, cursor
/// and size of page.
@DataClassName('MeetingPageRow')
class MeetingPages extends Table {
  /// The user whose session fetched the page.
  TextColumn get owner => text()();

  /// The period of the list.
  TextColumn get period => text()();

  /// The cursor of the page, as JSON.
  TextColumn get cursorKey => text()();

  /// The size of the page.
  IntColumn get pageLimit => integer()();

  /// When the page was cached.
  IntColumn get cachedAt => integer()();

  /// The page, as JSON.
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {owner, period, cursorKey, pageLimit};

  @override
  bool get withoutRowId => true;
}

/// The meetings viewed, one row for each owner and meeting.
@DataClassName('MeetingDetailRow')
class MeetingDetails extends Table {
  /// The user whose session fetched the meeting.
  TextColumn get owner => text()();

  /// The meeting.
  TextColumn get meetingId => text()();

  /// When the meeting was cached.
  IntColumn get cachedAt => integer()();

  /// The meeting, as JSON.
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {owner, meetingId};

  @override
  bool get withoutRowId => true;
}
