import 'package:drift/drift.dart';

// The table of the documents as drift knows it: the names and the types of the
// columns, for the queries that write to them. The database itself is
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

/// The documents already viewed, one row for each owner and document.
@DataClassName('DocumentEntryRow')
class DocumentEntries extends Table {
  /// The user whose session fetched the document.
  TextColumn get owner => text()();

  /// The document.
  TextColumn get documentId => text()();

  /// When the document was cached.
  IntColumn get cachedAt => integer()();

  /// Where the content is.
  TextColumn get location => text()();

  /// The metadata of the document, as JSON.
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {owner, documentId};

  @override
  bool get withoutRowId => true;
}
