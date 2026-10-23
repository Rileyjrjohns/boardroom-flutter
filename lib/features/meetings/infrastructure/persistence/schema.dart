import 'package:boardroom/core/domain/shared/constants.dart';

// The names of what the meetings store on the device. They are part of the
// format of the database: a database created by an older version of the app has
// these names in it. Changing one is a migration (see
// `lib/app/persistence/migrations.dart`, which lists the history of the whole
// file and reads these names), never an edit of a constant.

/// The tables of the meetings.
enum MeetingStoredTable implements StableValue {
  /// The pages of the list of meetings.
  meetingPages('meeting_pages'),

  /// The meetings viewed.
  meetingDetails('meeting_details');

  new(this.value);

  @override
  final String value;
}

/// The columns of the tables of the meetings.
enum MeetingStoredColumn implements StableValue {
  /// The user whose session fetched a cached entry.
  owner('owner'),

  /// The period of a cached page.
  period('period'),

  /// The cursor of a cached page, written as JSON: `null` for the first page.
  cursorKey('cursor_key'),

  /// The size of a cached page.
  pageLimit('page_limit'),

  /// The meeting of a cached meeting.
  meetingId('meeting_id'),

  /// When an entry was cached.
  cachedAt('cached_at'),

  /// The page or the meeting as the cache writes it, as JSON.
  payload('payload');

  new(this.value);

  @override
  final String value;
}
