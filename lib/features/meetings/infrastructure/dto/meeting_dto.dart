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

part 'meeting_dto.g.dart';

// The meetings of the API: `GET /meetings` (a page of summaries) and
// `GET /meetings/{id}`.
//
// A wire class checks that each field is there and has the type of the API, and
// ignores the fields it does not know. The values themselves are checked by the
// factories of the domain, in the mappers: a status that is not one, a blank
// title, a duplicate id. An instant is an ISO 8601 string.

/// The fields of a summary of a meeting, which a meeting has too.
abstract interface class MeetingSummaryFields {
  /// The identifier of the meeting.
  String get id;

  /// The title of the meeting.
  String get title;

  /// When the meeting starts, in milliseconds since the epoch.
  int get scheduledAt;

  /// Where the meeting takes place.
  String get location;
}

/// A resolution of an agenda item as the API writes it.
@JsonSerializable(checked: true, includeIfNull: false)
final class ResolutionWire {
  /// Creates the wire form of a resolution.
  const new({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.closesAt,
    this.recordedVote,
  });

  /// Reads the wire form of a resolution, or throws a
  /// `CheckedFromJsonException` at the first field that is missing or has the
  /// wrong type.
  factory fromJson(Map<String, dynamic> json) => _$ResolutionWireFromJson(json);

  /// The identifier of the resolution.
  final String id;

  /// The title of the resolution.
  final String title;

  /// The description of the resolution.
  final String description;

  /// The status, as the API names it.
  final String status;

  /// When voting closes, in milliseconds since the epoch.
  @JsonKey(
    fromJson: readInstantMillis,
    toJson: writeOptionalInstantMillis,
    disallowNullValue: true,
  )
  final int? closesAt;

  /// The choice the caller recorded, as the API names it.
  @JsonKey(disallowNullValue: true)
  final String? recordedVote;

  /// The JSON object of this resolution.
  Map<String, dynamic> toJson() => _$ResolutionWireToJson(this);
}

/// An item of the agenda as the API writes it.
@JsonSerializable(checked: true, includeIfNull: false, explicitToJson: true)
final class AgendaItemWire {
  /// Creates the wire form of an agenda item.
  const new({
    required this.id,
    required this.position,
    required this.title,
    this.description,
    this.resolution,
  });

  /// Reads the wire form of an agenda item, or throws a
  /// `CheckedFromJsonException` at the first field that is missing or has the
  /// wrong type.
  factory fromJson(Map<String, dynamic> json) => _$AgendaItemWireFromJson(json);

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
  final ResolutionWire? resolution;

  /// The JSON object of this item.
  Map<String, dynamic> toJson() => _$AgendaItemWireToJson(this);
}

/// A participant of a meeting as the API writes it.
@JsonSerializable(checked: true)
final class ParticipantWire {
  /// Creates the wire form of a participant.
  const new({required this.userId, required this.fullName, required this.role});

  /// Reads the wire form of a participant, or throws a
  /// `CheckedFromJsonException` at the first field that is missing or has the
  /// wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$ParticipantWireFromJson(json);

  /// The identifier of the user.
  final String userId;

  /// The full name of the participant.
  final String fullName;

  /// The role, as the API names it.
  final String role;

  /// The JSON object of this participant.
  Map<String, dynamic> toJson() => _$ParticipantWireToJson(this);
}

/// A document as a meeting lists it: its description, as the API writes it in
/// the meeting. The `Document` is an entity of the meetings, so the meetings
/// read it themselves; the documents have a form of their own for the
/// answer of `GET /documents/{id}` (an adapter does not import the adapter of
/// another feature).
@JsonSerializable(checked: true)
final class MeetingDocumentWire {
  /// Creates the wire form of a document of a meeting.
  const new({
    required this.id,
    required this.title,
    required this.confidentiality,
    required this.pageCount,
  });

  /// Reads the wire form of a document of a meeting, or throws a
  /// `CheckedFromJsonException` at the first field that is missing or has the
  /// wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$MeetingDocumentWireFromJson(json);

  /// The identifier of the document.
  final String id;

  /// The title of the document.
  final String title;

  /// The confidentiality level, as the API names it.
  final String confidentiality;

  /// The number of pages the document says it has.
  final num pageCount;

  /// The JSON object of this document.
  Map<String, dynamic> toJson() => _$MeetingDocumentWireToJson(this);
}

/// A summary of a meeting, an item of `GET /meetings`.
@JsonSerializable(checked: true)
final class MeetingSummaryWire implements MeetingSummaryFields {
  /// Creates the wire form of a summary.
  const new({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.location,
  });

  /// Reads the wire form of a summary, or throws a `CheckedFromJsonException`
  /// at the first field that is missing or has the wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$MeetingSummaryWireFromJson(json);

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
  Map<String, dynamic> toJson() => _$MeetingSummaryWireToJson(this);
}

/// A meeting with its agenda, documents and participants:
/// `GET /meetings/{id}`.
@JsonSerializable(checked: true, explicitToJson: true)
final class MeetingWire implements MeetingSummaryFields {
  /// Creates the wire form of a meeting.
  const new({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.location,
    required this.agenda,
    required this.documents,
    required this.participants,
  });

  /// Reads the wire form of a meeting, or throws a `CheckedFromJsonException`
  /// at the first field that is missing or has the wrong type.
  factory fromJson(Map<String, dynamic> json) => _$MeetingWireFromJson(json);

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
  final List<AgendaItemWire> agenda;

  /// The documents of the meeting.
  final List<MeetingDocumentWire> documents;

  /// The people of the meeting.
  final List<ParticipantWire> participants;

  /// The JSON object of this meeting.
  Map<String, dynamic> toJson() => _$MeetingWireToJson(this);
}

/// A page of summaries: the answer of `GET /meetings`.
@JsonSerializable(checked: true, includeIfNull: false, explicitToJson: true)
final class MeetingPageWire {
  /// Creates the wire form of a page.
  const new({required this.items, this.nextCursor});

  /// Reads the wire form of a page, or throws a `CheckedFromJsonException` at
  /// the first field that is missing or has the wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$MeetingPageWireFromJson(json);

  /// The summaries of the page.
  final List<MeetingSummaryWire> items;

  /// Where the next page starts, absent on the last page.
  @JsonKey(disallowNullValue: true)
  final String? nextCursor;

  /// The JSON object of this page.
  Map<String, dynamic> toJson() => _$MeetingPageWireToJson(this);
}

/// The summary a wire form describes (a summary, or a meeting), through the
/// factories of the domain.
Result<MeetingSummary, ValidationError> toMeetingSummary(
  MeetingSummaryFields wire,
) => andThen(
  parseMeetingId(wire.id),
  (id) => andThen(
    parseInstant(wire.scheduledAt),
    (scheduledAt) => createMeetingSummary(
      MeetingSummaryInput(
        id: id,
        title: wire.title,
        scheduledAt: scheduledAt,
        location: wire.location,
      ),
    ),
  ),
);

/// The result of [read] on a value that may be missing: a missing value is a
/// success, with nothing.
Result<T?, ValidationError> _optional<W, T>(
  W? wire,
  Result<T, ValidationError> Function(W value) read,
) => wire == null ? ok<T?>(null) : read(wire);

Result<Resolution, ValidationError> _toResolution(ResolutionWire wire) =>
    andThen(
      parseResolutionId(wire.id),
      (id) => andThen(
        parseResolutionStatus(wire.status),
        (status) => andThen(
          _optional(wire.closesAt, parseInstant),
          (closesAt) => andThen(
            _optional(wire.recordedVote, parseVoteChoice),
            (recordedVote) => createResolution(
              ResolutionInput(
                id: id,
                title: wire.title,
                description: wire.description,
                status: status,
                closesAt: closesAt,
                recordedVote: recordedVote,
              ),
            ),
          ),
        ),
      ),
    );

Result<AgendaItem, ValidationError> _toAgendaItem(AgendaItemWire wire) =>
    andThen(
      parseAgendaItemId(wire.id),
      (id) => andThen(
        _optional(wire.resolution, _toResolution),
        (resolution) => createAgendaItem(
          AgendaItemInput(
            id: id,
            position: wire.position,
            title: wire.title,
            description: wire.description,
            resolution: resolution,
          ),
        ),
      ),
    );

Result<Participant, ValidationError> _toParticipant(ParticipantWire wire) =>
    andThen(
      parseUserId(wire.userId),
      (userId) => andThen(
        parseParticipantRole(wire.role),
        (role) => createParticipant(
          userId: userId,
          fullName: wire.fullName,
          role: role,
        ),
      ),
    );

Result<Document, ValidationError> _toDocument(MeetingDocumentWire wire) =>
    andThen(
      parseDocumentId(wire.id),
      (id) => andThen(
        parseConfidentialityLevel(wire.confidentiality),
        (confidentiality) => createDocument(
          DocumentInput(
            id: id,
            title: wire.title,
            confidentiality: confidentiality,
            pageCount: wire.pageCount,
          ),
        ),
      ),
    );

MeetingDocumentWire _toDocumentWire(Document document) => MeetingDocumentWire(
  id: document.id,
  title: document.title,
  confidentiality: document.confidentiality.value,
  pageCount: document.pageCount,
);

/// The meeting a wire form describes, through the factories of the domain.
Result<Meeting, ValidationError> toMeeting(MeetingWire wire) => andThen(
  toMeetingSummary(wire),
  (summary) => andThen(
    collect(wire.agenda.map(_toAgendaItem)),
    (agenda) => andThen(
      collect(wire.documents.map(_toDocument)),
      (documents) => andThen(
        collect(wire.participants.map(_toParticipant)),
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

/// The page a wire form describes, through the factories of the domain.
Result<Page<MeetingSummary>, ValidationError> toMeetingPage(
  MeetingPageWire wire,
) => andThen(
  collect(wire.items.map(toMeetingSummary)),
  (items) => andThen(
    _optional(wire.nextCursor, parsePageCursor),
    (nextCursor) => ok(createPage(items, nextCursor)),
  ),
);

/// A summary, written as the API writes it.
MeetingSummaryWire toMeetingSummaryWire(MeetingSummary summary) =>
    MeetingSummaryWire(
      id: summary.id,
      title: summary.title,
      scheduledAt: summary.scheduledAt,
      location: summary.location,
    );

ResolutionWire _toResolutionWire(Resolution resolution) => ResolutionWire(
  id: resolution.id,
  title: resolution.title,
  description: resolution.description,
  status: resolution.status.value,
  closesAt: resolution.closesAt,
  recordedVote: resolution.recordedVote?.value,
);

AgendaItemWire _toAgendaItemWire(AgendaItem item) => AgendaItemWire(
  id: item.id,
  position: item.position,
  title: item.title,
  description: item.description,
  resolution: item.resolution == null
      ? null
      : _toResolutionWire(item.resolution!),
);

/// A meeting, written as the API writes it.
MeetingWire toMeetingWire(Meeting meeting) => MeetingWire(
  id: meeting.id,
  title: meeting.title,
  scheduledAt: meeting.scheduledAt,
  location: meeting.location,
  agenda: meeting.agenda.map(_toAgendaItemWire).toList(),
  documents: meeting.documents.map(_toDocumentWire).toList(),
  participants: [
    for (final participant in meeting.participants)
      ParticipantWire(
        userId: participant.userId,
        fullName: participant.fullName,
        role: participant.role.value,
      ),
  ],
);

/// A page of summaries, written as the API writes it.
MeetingPageWire toMeetingPageWire(Page<MeetingSummary> page) => MeetingPageWire(
  items: page.items.map(toMeetingSummaryWire).toList(),
  nextCursor: page.nextCursor,
);
