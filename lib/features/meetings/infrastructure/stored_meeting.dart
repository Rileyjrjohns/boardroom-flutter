import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/domain/value_objects/page.dart';
import 'package:boardroom/core/domain/value_objects/page_cursor.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/core/infrastructure/shared/results.dart';
import 'package:boardroom/features/meetings/domain/entities/agenda_item.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:json_annotation/json_annotation.dart';

part 'stored_meeting.g.dart';

// What the cache of meetings keeps in a row, on the device: the format of the
// database, which is the cache's own and not the API's. It is described here,
// apart from the DTOs of the API, so that a change of the API (a field renamed,
// an instant written another way) does not make the rows that were stored
// unreadable, and a change of what is stored is a migration of its own. It
// happens to look like what the API wrote when the cache was first written, and
// the rows that were stored then are read as they are (a test holds one, as it
// was written). Changing it means reading the rows of before too, or discarding
// them on purpose.
//
// A class checks that each field is there and has the type that was stored, and
// ignores the ones it does not know. The values themselves are checked by the
// factories of the domain. An instant is stored as an ISO 8601 text with a
// zone.

/// A resolution as the cache keeps it.
@JsonSerializable(checked: true, includeIfNull: false)
final class StoredResolution {
  /// Creates the stored form of a resolution.
  const new({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.closesAt,
    this.recordedVote,
  });

  /// Reads the stored form of a resolution, or throws a
  /// `CheckedFromJsonException` at the first field that is missing or has the
  /// wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$StoredResolutionFromJson(json);

  /// The identifier of the resolution.
  final String id;

  /// The title of the resolution.
  final String title;

  /// The description of the resolution.
  final String description;

  /// The status, as the cache names it.
  final String status;

  /// When voting closes, in milliseconds since the epoch.
  @JsonKey(
    fromJson: readInstantMillis,
    toJson: writeOptionalInstantMillis,
    disallowNullValue: true,
  )
  final int? closesAt;

  /// The choice the caller recorded, as the cache names it.
  @JsonKey(disallowNullValue: true)
  final String? recordedVote;

  /// The JSON object of this resolution.
  Map<String, dynamic> toJson() => _$StoredResolutionToJson(this);
}

/// An item of the agenda as the cache keeps it.
@JsonSerializable(checked: true, includeIfNull: false, explicitToJson: true)
final class StoredAgendaItem {
  /// Creates the stored form of an agenda item.
  const new({
    required this.id,
    required this.position,
    required this.title,
    this.description,
    this.resolution,
  });

  /// Reads the stored form of an agenda item, or throws a
  /// `CheckedFromJsonException` at the first field that is missing or has the
  /// wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$StoredAgendaItemFromJson(json);

  /// The identifier of the agenda item.
  final String id;

  /// The position in the agenda.
  final num position;

  /// The title of the item.
  final String title;

  /// The description of the item.
  @JsonKey(disallowNullValue: true)
  final String? description;

  /// The resolution put to the vote under this item.
  @JsonKey(disallowNullValue: true)
  final StoredResolution? resolution;

  /// The JSON object of this item.
  Map<String, dynamic> toJson() => _$StoredAgendaItemToJson(this);
}

/// A participant as the cache keeps it.
@JsonSerializable(checked: true)
final class StoredParticipant {
  /// Creates the stored form of a participant.
  const new({required this.userId, required this.fullName, required this.role});

  /// Reads the stored form of a participant, or throws a
  /// `CheckedFromJsonException` at the first field that is missing or has the
  /// wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$StoredParticipantFromJson(json);

  /// The identifier of the user.
  final String userId;

  /// The full name of the participant.
  final String fullName;

  /// The role, as the cache names it.
  final String role;

  /// The JSON object of this participant.
  Map<String, dynamic> toJson() => _$StoredParticipantToJson(this);
}

/// A document of a meeting as the cache keeps it in the row of the meeting: its
/// description. The documents keep a form of their own in the row of a document
/// (an adapter does not import the adapter of another feature, and the two rows
/// have each their own format).
@JsonSerializable(checked: true)
final class StoredMeetingDocument {
  /// Creates the stored form of a document of a meeting.
  const new({
    required this.id,
    required this.title,
    required this.confidentiality,
    required this.pageCount,
  });

  /// Reads the stored form of a document of a meeting, or throws a
  /// `CheckedFromJsonException` at the first field that is missing or has the
  /// wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$StoredMeetingDocumentFromJson(json);

  /// The identifier of the document.
  final String id;

  /// The title of the document.
  final String title;

  /// The level of confidentiality, as the cache names it.
  final String confidentiality;

  /// The number of pages.
  final num pageCount;

  /// The JSON object of this document.
  Map<String, dynamic> toJson() => _$StoredMeetingDocumentToJson(this);
}

/// The fields of a summary of a meeting, which a meeting has too.
abstract interface class StoredSummaryFields {
  /// The identifier of the meeting.
  String get id;

  /// The title of the meeting.
  String get title;

  /// When the meeting starts, in milliseconds since the epoch.
  int get scheduledAt;

  /// Where the meeting takes place.
  String get location;
}

/// A summary of a meeting as the cache keeps it.
@JsonSerializable(checked: true)
final class StoredSummary implements StoredSummaryFields {
  /// Creates the stored form of a summary.
  const new({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.location,
  });

  /// Reads the stored form of a summary, or throws a
  /// `CheckedFromJsonException` at the first field that is missing or has the
  /// wrong type.
  factory fromJson(Map<String, dynamic> json) => _$StoredSummaryFromJson(json);

  @override
  final String id;

  @override
  final String title;

  @override
  @JsonKey(fromJson: readInstantMillis, toJson: writeInstantMillis)
  final int scheduledAt;

  @override
  final String location;

  /// The JSON object of this summary.
  Map<String, dynamic> toJson() => _$StoredSummaryToJson(this);
}

/// A meeting as the cache keeps it.
@JsonSerializable(checked: true, explicitToJson: true)
final class StoredMeeting implements StoredSummaryFields {
  /// Creates the stored form of a meeting.
  const new({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.location,
    required this.agenda,
    required this.documents,
    required this.participants,
  });

  /// Reads the stored form of a meeting, or throws a
  /// `CheckedFromJsonException` at the first field that is missing or has the
  /// wrong type.
  factory fromJson(Map<String, dynamic> json) => _$StoredMeetingFromJson(json);

  @override
  final String id;

  @override
  final String title;

  @override
  @JsonKey(fromJson: readInstantMillis, toJson: writeInstantMillis)
  final int scheduledAt;

  @override
  final String location;

  /// The items of the agenda.
  final List<StoredAgendaItem> agenda;

  /// The documents of the meeting.
  final List<StoredMeetingDocument> documents;

  /// The people of the meeting.
  final List<StoredParticipant> participants;

  /// The JSON object of this meeting.
  Map<String, dynamic> toJson() => _$StoredMeetingToJson(this);
}

/// A page of the list of meetings as the cache keeps it.
@JsonSerializable(checked: true, includeIfNull: false, explicitToJson: true)
final class StoredMeetingPage {
  /// Creates the stored form of a page.
  const new({required this.items, this.nextCursor});

  /// Reads the stored form of a page, or throws a `CheckedFromJsonException` at
  /// the first field that is missing or has the wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$StoredMeetingPageFromJson(json);

  /// The summaries of the page.
  final List<StoredSummary> items;

  /// Where the next page starts, absent on the last page.
  @JsonKey(disallowNullValue: true)
  final String? nextCursor;

  /// The JSON object of this page.
  Map<String, dynamic> toJson() => _$StoredMeetingPageToJson(this);
}

/// The result of [read] on a value that may be missing: a missing value is a
/// success, with nothing.
Result<T?, ValidationError> _optional<S, T>(
  S? stored,
  Result<T, ValidationError> Function(S value) read,
) => stored == null ? ok<T?>(null) : read(stored);

Result<Resolution, ValidationError> _resolutionOf(StoredResolution stored) =>
    andThen(
      parseResolutionId(stored.id),
      (id) => andThen(
        parseResolutionStatus(stored.status),
        (status) => andThen(
          _optional(stored.closesAt, parseInstant),
          (closesAt) => andThen(
            _optional(stored.recordedVote, parseVoteChoice),
            (recordedVote) => createResolution(
              ResolutionInput(
                id: id,
                title: stored.title,
                description: stored.description,
                status: status,
                closesAt: closesAt,
                recordedVote: recordedVote,
              ),
            ),
          ),
        ),
      ),
    );

Result<AgendaItem, ValidationError> _agendaItemOf(StoredAgendaItem stored) =>
    andThen(
      parseAgendaItemId(stored.id),
      (id) => andThen(
        _optional(stored.resolution, _resolutionOf),
        (resolution) => createAgendaItem(
          AgendaItemInput(
            id: id,
            position: stored.position,
            title: stored.title,
            description: stored.description,
            resolution: resolution,
          ),
        ),
      ),
    );

Result<Participant, ValidationError> _participantOf(StoredParticipant stored) =>
    andThen(
      parseUserId(stored.userId),
      (userId) => andThen(
        parseParticipantRole(stored.role),
        (role) => createParticipant(
          userId: userId,
          fullName: stored.fullName,
          role: role,
        ),
      ),
    );

Result<Document, ValidationError> _documentOf(StoredMeetingDocument stored) =>
    andThen(
      parseDocumentId(stored.id),
      (id) => andThen(
        parseConfidentialityLevel(stored.confidentiality),
        (confidentiality) => createDocument(
          DocumentInput(
            id: id,
            title: stored.title,
            confidentiality: confidentiality,
            pageCount: stored.pageCount,
          ),
        ),
      ),
    );

StoredMeetingDocument _storedDocumentOf(Document document) =>
    StoredMeetingDocument(
      id: document.id,
      title: document.title,
      confidentiality: document.confidentiality.value,
      pageCount: document.pageCount,
    );

Result<MeetingSummary, ValidationError> _summaryOf(
  StoredSummaryFields stored,
) => andThen(
  parseMeetingId(stored.id),
  (id) => andThen(
    parseInstant(stored.scheduledAt),
    (scheduledAt) => createMeetingSummary(
      MeetingSummaryInput(
        id: id,
        title: stored.title,
        scheduledAt: scheduledAt,
        location: stored.location,
      ),
    ),
  ),
);

/// The meeting a row holds, through the factories of the domain.
Result<Meeting, ValidationError> meetingOf(StoredMeeting stored) => andThen(
  _summaryOf(stored),
  (summary) => andThen(
    collect(stored.agenda.map(_agendaItemOf)),
    (agenda) => andThen(
      collect(stored.documents.map(_documentOf)),
      (documents) => andThen(
        collect(stored.participants.map(_participantOf)),
        (participants) => createMeeting(
          MeetingInput(
            summary: summary,
            agenda: agenda,
            documents: documents,
            participants: participants,
          ),
        ),
      ),
    ),
  ),
);

/// The page a row holds, through the factories of the domain.
Result<Page<MeetingSummary>, ValidationError> pageOf(
  StoredMeetingPage stored,
) => andThen(
  collect(stored.items.map(_summaryOf)),
  (items) => andThen(
    _optional(stored.nextCursor, parsePageCursor),
    (nextCursor) => ok(createPage(items, nextCursor)),
  ),
);

StoredSummary _storedSummary(MeetingSummary summary) => StoredSummary(
  id: summary.id,
  title: summary.title,
  scheduledAt: summary.scheduledAt,
  location: summary.location,
);

StoredResolution _storedResolution(Resolution resolution) => StoredResolution(
  id: resolution.id,
  title: resolution.title,
  description: resolution.description,
  status: resolution.status.value,
  closesAt: resolution.closesAt,
  recordedVote: resolution.recordedVote?.value,
);

StoredAgendaItem _storedAgendaItem(AgendaItem item) => StoredAgendaItem(
  id: item.id,
  position: item.position,
  title: item.title,
  description: item.description,
  resolution: item.resolution == null
      ? null
      : _storedResolution(item.resolution!),
);

/// What is written in a row for a meeting.
StoredMeeting storedMeetingOf(Meeting meeting) => StoredMeeting(
  id: meeting.id,
  title: meeting.title,
  scheduledAt: meeting.scheduledAt,
  location: meeting.location,
  agenda: meeting.agenda.map(_storedAgendaItem).toList(),
  documents: meeting.documents.map(_storedDocumentOf).toList(),
  participants: [
    for (final participant in meeting.participants)
      StoredParticipant(
        userId: participant.userId,
        fullName: participant.fullName,
        role: participant.role.value,
      ),
  ],
);

/// What is written in a row for a page of the list.
StoredMeetingPage storedPageOf(Page<MeetingSummary> page) => StoredMeetingPage(
  items: page.items.map(_storedSummary).toList(),
  nextCursor: page.nextCursor,
);
