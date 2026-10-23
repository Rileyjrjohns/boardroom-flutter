import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/domain/entities/user.dart';
import 'package:boardroom/features/auth/domain/value_objects/email_address.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:boardroom/features/meetings/domain/entities/agenda_item.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';

// Test support, not production code: the files of a `support` folder may throw,
// which is how a fixture that breaks an invariant fails the test that uses it.
// Nothing in lib/ imports them (tool/check_imports.dart enforces it).

/// The value of a success. A failure is a broken fixture, and it fails the test
/// with its error.
T unwrap<T, E>(Result<T, E> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => throw StateError('Invalid fixture: $error'),
};

/// The instant of the tests: 2030-03-17T17:46:40Z. Nothing in a test reads the
/// real clock.
final Instant now = unwrap(parseInstant(1900000000000));

/// Milliseconds in a minute.
const int millisPerMinute = 60000;

/// Milliseconds in an hour.
const int millisPerHour = 60 * millisPerMinute;

/// Milliseconds in a day.
const int millisPerDay = 24 * millisPerHour;

/// [now] shifted by [millis], which may be negative.
Instant at(int millis) => unwrap(parseInstant(now + millis));

/// [instant] shifted forward by [millis].
Instant after(Instant instant, int millis) =>
    unwrap(plus(instant, unwrap(durationFromMillis(millis))));

/// A duration of [millis] milliseconds.
DurationMillis aDuration(int millis) => unwrap(durationFromMillis(millis));

/// A user id, `user-1` unless [raw] is given.
UserId aUserId([String raw = 'user-1']) => unwrap(parseUserId(raw));

/// A meeting id, `meeting-1` unless [raw] is given.
MeetingId aMeetingId([String raw = 'meeting-1']) => unwrap(parseMeetingId(raw));

/// An agenda item id, `agenda-1` unless [raw] is given.
AgendaItemId anAgendaItemId([String raw = 'agenda-1']) =>
    unwrap(parseAgendaItemId(raw));

/// A resolution id, `resolution-1` unless [raw] is given.
ResolutionId aResolutionId([String raw = 'resolution-1']) =>
    unwrap(parseResolutionId(raw));

/// A document id, `document-1` unless [raw] is given.
DocumentId aDocumentId([String raw = 'document-1']) =>
    unwrap(parseDocumentId(raw));

/// An email address, `alice@example.com` unless [raw] is given.
EmailAddress anEmail([String raw = 'alice@example.com']) =>
    unwrap(parseEmailAddress(raw));

/// A document location, a PDF of the private storage unless [raw] is given.
DocumentLocation aDocumentLocation([
  String raw = 'file:///documents/document-1.pdf',
]) => unwrap(parseDocumentLocation(raw));

/// A user, Alice Martin unless the arguments say otherwise.
User aUser({UserId? id, String? fullName, EmailAddress? email}) => unwrap(
  createUser(
    id: id ?? aUserId(),
    fullName: fullName ?? 'Alice Martin',
    email: email ?? anEmail(),
  ),
);

/// A session that ends one hour after [now].
Session aSession({User? user, Instant? expiresAt}) => createSession(
  user: user ?? aUser(),
  expiresAt: expiresAt ?? at(millisPerHour),
);

/// A member of the board, who can vote.
Participant aParticipant({
  UserId? userId,
  String? fullName,
  ParticipantRole role = ParticipantRole.member,
}) => unwrap(
  createParticipant(
    userId: userId ?? aUserId(),
    fullName: fullName ?? 'Alice Martin',
    role: role,
  ),
);

/// An internal document of three pages.
Document aDocument({
  DocumentId? id,
  String title = 'Financial statements',
  ConfidentialityLevel confidentiality = ConfidentialityLevel.internal,
  num pageCount = 3,
}) => unwrap(
  createDocument(
    DocumentInput(
      id: id ?? aDocumentId(),
      title: title,
      confidentiality: confidentiality,
      pageCount: pageCount,
    ),
  ),
);

/// A confidential document of three pages.
Document aConfidentialDocument({
  DocumentId? id,
  String title = 'Financial statements',
  ConfidentialityLevel confidentiality = ConfidentialityLevel.confidential,
  num pageCount = 3,
}) => aDocument(
  id: id,
  title: title,
  confidentiality: confidentiality,
  pageCount: pageCount,
);

/// An open resolution, without a closing instant and without a recorded vote.
Resolution aResolution({
  ResolutionId? id,
  String title = 'Approve the budget',
  String description = 'Approve the budget of the next financial year.',
  ResolutionStatus status = ResolutionStatus.open,
  Instant? closesAt,
  VoteChoice? recordedVote,
}) => unwrap(
  createResolution(
    ResolutionInput(
      id: id ?? aResolutionId(),
      title: title,
      description: description,
      status: status,
      closesAt: closesAt,
      recordedVote: recordedVote,
    ),
  ),
);

/// An agenda item at position 1, holding [aResolution] unless [resolution] is
/// given.
AgendaItem anAgendaItem({
  AgendaItemId? id,
  num position = 1,
  String title = 'Budget',
  String? description,
  Resolution? resolution,
}) => unwrap(
  createAgendaItem(
    AgendaItemInput(
      id: id ?? anAgendaItemId(),
      position: position,
      title: title,
      description: description,
      resolution: resolution ?? aResolution(),
    ),
  ),
);

/// A meeting scheduled one day after [now].
MeetingSummary aMeetingSummary({
  MeetingId? id,
  String title = 'Board of directors',
  Instant? scheduledAt,
  String location = 'Room 1',
}) => unwrap(
  createMeetingSummary(
    MeetingSummaryInput(
      id: id ?? aMeetingId(),
      title: title,
      scheduledAt: scheduledAt ?? at(millisPerDay),
      location: location,
    ),
  ),
);

/// A meeting with one agenda item holding an open resolution
/// (`aResolutionId()`), one confidential document (`aDocumentId()`), and four
/// participants: `user-1` is a member and can vote, `user-2` is the chair and
/// can vote, `user-3` is the secretary and `user-4` a guest, who cannot.
Meeting aMeeting({
  MeetingSummary? summary,
  List<AgendaItem>? agenda,
  List<Document>? documents,
  List<Participant>? participants,
}) => unwrap(
  createMeeting(
    MeetingInput(
      summary: summary ?? aMeetingSummary(),
      agenda: agenda ?? [anAgendaItem()],
      documents: documents ?? [aConfidentialDocument()],
      participants:
          participants ??
          [
            aParticipant(),
            aParticipant(
              userId: aUserId('user-2'),
              fullName: 'Bruno Durand',
              role: ParticipantRole.chair,
            ),
            aParticipant(
              userId: aUserId('user-3'),
              fullName: 'Chloe Petit',
              role: ParticipantRole.secretary,
            ),
            aParticipant(
              userId: aUserId('user-4'),
              fullName: 'David Roux',
              role: ParticipantRole.guest,
            ),
          ],
    ),
  ),
);

/// The same meeting with a longer agenda: an item without resolution (position
/// 1), then the open resolution `aResolutionId()` in the item at position 2,
/// then another open resolution, `aResolutionId('resolution-2')`, in the item
/// at position 3. Whatever looks only at the first item of the agenda finds
/// nothing here.
Meeting aMeetingWithAgenda({
  MeetingSummary? summary,
  List<AgendaItem>? agenda,
  List<Document>? documents,
  List<Participant>? participants,
}) {
  final base = aMeeting();
  return unwrap(
    createMeeting(
      MeetingInput(
        summary: summary ?? aMeetingSummary(),
        agenda:
            agenda ??
            [
              unwrap(
                createAgendaItem(
                  AgendaItemInput(
                    id: anAgendaItemId('agenda-0'),
                    position: 1,
                    title: 'Opening',
                  ),
                ),
              ),
              anAgendaItem(position: 2),
              anAgendaItem(
                id: anAgendaItemId('agenda-2'),
                position: 3,
                title: 'Elections',
                resolution: aResolution(
                  id: aResolutionId('resolution-2'),
                  title: 'Elect the chair',
                ),
              ),
            ],
        documents: documents ?? base.documents,
        participants: participants ?? base.participants,
      ),
    ),
  );
}

/// A vote of `user-1` on `resolution-1` of `meeting-1`: for, cast at [now].
Vote aVote({
  ResolutionId? resolutionId,
  MeetingId? meetingId,
  UserId? voterId,
  VoteChoice choice = VoteChoice.forChoice,
  Instant? castAt,
}) => createVote(
  VoteInput(
    resolutionId: resolutionId ?? aResolutionId(),
    meetingId: meetingId ?? aMeetingId(),
    voterId: voterId ?? aUserId(),
    choice: choice,
    castAt: castAt ?? now,
  ),
);

/// A vote waiting in the outbox since [enqueuedAt] ([now] unless given).
PendingVote aPendingVote([Vote? vote, Instant? enqueuedAt]) =>
    createPendingVote(vote ?? aVote(), enqueuedAt ?? now);

/// A vote the server refused because the resolution is closed, one minute
/// after [now].
RejectedVote aRejectedVote([
  Vote? vote,
  RejectionReason reason = const ResolutionClosedError(),
]) => rejectVote(aPendingVote(vote), reason, at(millisPerMinute));
