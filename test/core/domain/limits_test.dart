import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/domain/value_objects/page_cursor.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/features/auth/domain/entities/user.dart';
import 'package:boardroom/features/auth/domain/value_objects/email_address.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:boardroom/features/meetings/domain/entities/agenda_item.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:test/test.dart';

import '../../support/builders/builders.dart';

// Every limit of the domain, at its exact value: the maximum is accepted, one
// more is rejected (and, for a number, the minimum is accepted and one less is
// rejected).

typedef _Check = Result<Object?, Object?>;

typedef _LongText = (String, _Check Function(int), int, ValidationField);

typedef _Number = (String, _Check Function(num), int, int, ValidationField);

final List<_LongText> _longTexts = [
  (
    'an email address',
    (n) => parseEmailAddress('${'a' * (n - '@b.co'.length)}@b.co'),
    254,
    ValidationField.email,
  ),
  (
    'a document location',
    (n) => parseDocumentLocation('a' * n),
    2048,
    ValidationField.documentLocation,
  ),
  (
    'a page cursor',
    (n) => parsePageCursor('a' * n),
    512,
    ValidationField.pageCursor,
  ),
  ('a user id', (n) => parseUserId('a' * n), 128, ValidationField.userId),
  (
    'a meeting id',
    (n) => parseMeetingId('a' * n),
    128,
    ValidationField.meetingId,
  ),
  (
    'an agenda item id',
    (n) => parseAgendaItemId('a' * n),
    128,
    ValidationField.agendaItemId,
  ),
  (
    'a resolution id',
    (n) => parseResolutionId('a' * n),
    128,
    ValidationField.resolutionId,
  ),
  (
    'a document id',
    (n) => parseDocumentId('a' * n),
    128,
    ValidationField.documentId,
  ),
  (
    'the name of a user',
    (n) => createUser(id: aUserId(), fullName: 'a' * n, email: anEmail()),
    200,
    ValidationField.fullName,
  ),
  (
    'the name of a participant',
    (n) => createParticipant(
      userId: aUserId(),
      fullName: 'a' * n,
      role: ParticipantRole.member,
    ),
    200,
    ValidationField.fullName,
  ),
  (
    'the title of a document',
    (n) => createDocument(
      DocumentInput(
        id: aDocumentId(),
        title: 'a' * n,
        confidentiality: ConfidentialityLevel.internal,
        pageCount: 1,
      ),
    ),
    300,
    ValidationField.title,
  ),
  (
    'the title of a resolution',
    (n) => createResolution(
      ResolutionInput(
        id: aResolutionId(),
        title: 'a' * n,
        description: 'd',
        status: ResolutionStatus.open,
      ),
    ),
    300,
    ValidationField.title,
  ),
  (
    'the description of a resolution',
    (n) => createResolution(
      ResolutionInput(
        id: aResolutionId(),
        title: 't',
        description: 'a' * n,
        status: ResolutionStatus.open,
      ),
    ),
    5000,
    ValidationField.description,
  ),
  (
    'the title of an agenda item',
    (n) => createAgendaItem(
      AgendaItemInput(id: anAgendaItemId(), position: 1, title: 'a' * n),
    ),
    300,
    ValidationField.title,
  ),
  (
    'the description of an agenda item',
    (n) => createAgendaItem(
      AgendaItemInput(
        id: anAgendaItemId(),
        position: 1,
        title: 't',
        description: 'a' * n,
      ),
    ),
    5000,
    ValidationField.description,
  ),
  (
    'the title of a meeting',
    (n) => createMeetingSummary(
      MeetingSummaryInput(
        id: aMeetingId(),
        title: 'a' * n,
        scheduledAt: now,
        location: 'l',
      ),
    ),
    300,
    ValidationField.title,
  ),
  (
    'the location of a meeting',
    (n) => createMeetingSummary(
      MeetingSummaryInput(
        id: aMeetingId(),
        title: 't',
        scheduledAt: now,
        location: 'a' * n,
      ),
    ),
    300,
    ValidationField.location,
  ),
];

final List<_Number> _numbers = [
  (
    'the position of an agenda item',
    (position) => createAgendaItem(
      AgendaItemInput(id: anAgendaItemId(), position: position, title: 't'),
    ),
    1,
    1000,
    ValidationField.position,
  ),
  (
    'the page count of a document',
    (pageCount) => createDocument(
      DocumentInput(
        id: aDocumentId(),
        title: 't',
        confidentiality: ConfidentialityLevel.internal,
        pageCount: pageCount,
      ),
    ),
    1,
    10000,
    ValidationField.pageCount,
  ),
  (
    'the attempts of a pending vote',
    (attempts) =>
        restorePendingVote(vote: aVote(), enqueuedAt: now, attempts: attempts),
    0,
    1000000,
    ValidationField.attemptCount,
  ),
  (
    'the size of a page',
    (limit) => createPageRequest(limit: limit),
    1,
    50,
    ValidationField.pageLimit,
  ),
  (
    'a duration',
    durationFromMillis,
    0,
    3153600000000,
    ValidationField.duration,
  ),
  ('an instant', parseInstant, 0, 8640000000000000, ValidationField.instant),
];

void main() {
  for (final (name, build, maximum, field) in _longTexts) {
    group('the length of $name', () {
      test('accepts $maximum characters', () {
        expect(isOk(build(maximum)), isTrue);
      });

      test('rejects ${maximum + 1} characters as too long', () {
        expect(
          build(maximum + 1),
          equals(err(validationError(field, ValidationRule.tooLong))),
        );
      });
    });
  }

  for (final (name, build, minimum, maximum, field) in _numbers) {
    group(name, () {
      test('accepts $minimum and $maximum', () {
        expect(isOk(build(minimum)), isTrue);
        expect(isOk(build(maximum)), isTrue);
      });

      test('rejects ${minimum - 1} and ${maximum + 1}', () {
        final outOfRange = err(
          validationError(field, ValidationRule.outOfRange),
        );

        expect(build(minimum - 1), equals(outOfRange));
        expect(build(maximum + 1), equals(outOfRange));
      });
    });
  }
}
