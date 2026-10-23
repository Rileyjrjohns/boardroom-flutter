// The test ids of the meetings list and the meeting detail, declared by the
// feature that owns the screens and put together with the others by
// `lib/app/test_ids.dart`. Pure Dart, so that the conformance test of the
// specification can read them. The widgets set them as `Key(id)`; the values
// are the ones of docs/spec/screens.md.

/// The test ids of the meetings list and the meeting detail.
abstract final class MeetingsTestIds {
  /// The list of the selected period.
  static const String meetingsList = 'meetings-list';

  /// The first page is pending.
  static const String meetingsLoading = 'meetings-loading';

  /// No meetings and no error.
  static const String meetingsEmpty = 'meetings-empty';

  /// The first page failed.
  static const String meetingsError = 'meetings-error';

  /// The last page is loaded.
  static const String meetingsEnd = 'meetings-end';

  /// The next page is being fetched.
  static const String meetingsLoadingMore = 'meetings-loading-more';

  /// The next page failed.
  static const String meetingsLoadMoreError = 'meetings-load-more-error';

  /// The meeting is loaded.
  static const String meetingDetail = 'meeting-detail';

  /// The meeting is pending.
  static const String meetingLoading = 'meeting-loading';

  /// A final error other than not found.
  static const String meetingError = 'meeting-error';

  /// The parameter is invalid or the meeting does not exist.
  static const String meetingNotFound = 'meeting-not-found';

  /// The title of the loaded meeting.
  static const String meetingTitle = 'meeting-title';

  /// The agenda section.
  static const String agendaSection = 'agenda-section';

  /// The documents section.
  static const String documentsSection = 'documents-section';

  /// The participants section.
  static const String participantsSection = 'participants-section';
}

/// The prefix of the id of a row of the meetings list, for the flows that look
/// for any row.
const String meetingRowTestIdPrefix = 'meeting-row-';

/// A row of the meetings list, by meeting id.
String meetingRowTestId(String id) => '$meetingRowTestIdPrefix$id';

/// An option of the period control: `upcoming` or `past`.
String periodOptionTestId(String period) => 'period-option-$period';

/// An agenda item of the meeting, by agenda item id.
String agendaItemTestId(String id) => 'agenda-item-$id';

/// A resolution card, by resolution id.
String resolutionTestId(String id) => 'resolution-$id';

/// A document row of the meeting, by document id.
String documentTestId(String id) => 'document-$id';

/// A participant row, by the user id of the participant.
String participantTestId(String userId) => 'participant-$userId';
