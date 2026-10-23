import 'package:boardroom/core/domain/shared/constants.dart';

// The names of what the documents store on the device. They are part of the
// format of the database: a database created by an older version of the app has
// these names in it. Changing one is a migration (see
// `lib/app/persistence/migrations.dart`, which lists the history of the whole
// file and reads these names), never an edit of a constant.

/// The tables of the documents.
enum DocumentStoredTable implements StableValue {
  /// The documents already viewed, with where their content is. Added by
  /// version 4 of the schema.
  documentEntries('document_entries');

  new(this.value);

  @override
  final String value;
}

/// The columns of the tables of the documents.
enum DocumentStoredColumn implements StableValue {
  /// The user whose session fetched a cached entry.
  owner('owner'),

  /// The document of a cached document.
  documentId('document_id'),

  /// Where the content of a cached document is: the location the repository
  /// handed out.
  location('location'),

  /// When an entry was cached.
  cachedAt('cached_at'),

  /// The metadata of the document as the cache writes it, as JSON.
  payload('payload');

  new(this.value);

  @override
  final String value;
}

/// The indexes of the tables of the documents.
enum DocumentStoredIndex implements StableValue {
  /// Finds the entries that point at a file, to know whether another one still
  /// needs it.
  documentEntriesByLocation('document_entries_by_location');

  new(this.value);

  @override
  final String value;
}
