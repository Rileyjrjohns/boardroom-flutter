// The arguments restate the values of the scenario, even when they are the
// defaults of the builders.
// ignore_for_file: avoid_redundant_argument_values

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/meetings/domain/entities/agenda_item.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';

/// A scenario of duplicates: its name, the input and the field that repeats.
typedef _DuplicateRow = (String, MeetingInput, ValidationField);

/// An agenda item with neither description nor resolution.
AgendaItem _plainItem(String id, int position) => unwrap(
  createAgendaItem(
    AgendaItemInput(
      id: anAgendaItemId(id),
      position: position,
      title: 'Item $position',
    ),
  ),
);

MeetingInput _base({
  List<AgendaItem> agenda = const [],
  List<Document> documents = const [],
  List<Participant> participants = const [],
}) => MeetingInput(
  summary: aMeetingSummary(),
  agenda: agenda,
  documents: documents,
  participants: participants,
);

void main() {
  group('createMeeting', () {
    test('spreads the summary fields and sorts the agenda by position', () {
      final second = anAgendaItem(
        id: anAgendaItemId('agenda-2'),
        position: 2,
        resolution: aResolution(id: aResolutionId('resolution-2')),
      );
      final first = anAgendaItem();

      final meeting = unwrap(createMeeting(_base(agenda: [second, first])));

      final summary = aMeetingSummary();
      expect(
        meeting,
        equals(
          Meeting(
            id: summary.id,
            title: summary.title,
            scheduledAt: summary.scheduledAt,
            location: summary.location,
            agenda: [first, second],
            documents: const [],
            participants: const [],
          ),
        ),
      );
    });

    test('does not reorder the agenda it is given', () {
      final second = anAgendaItem(
        id: anAgendaItemId('agenda-2'),
        position: 2,
        resolution: aResolution(id: aResolutionId('resolution-2')),
      );
      final agenda = [second, anAgendaItem()];

      unwrap(createMeeting(_base(agenda: agenda)));

      expect(agenda[0], same(second));
    });

    test(
      'copies the agenda, the documents and the participants it is given',
      () {
        final agenda = [anAgendaItem()];
        final documents = [aDocument()];
        final participants = [aParticipant()];
        final meeting = unwrap(
          createMeeting(
            _base(
              agenda: agenda,
              documents: documents,
              participants: participants,
            ),
          ),
        );

        agenda.add(_plainItem('agenda-9', 9));
        documents.add(aDocument(id: aDocumentId('document-2')));
        participants.add(aParticipant(userId: aUserId('user-9')));

        expect(meeting.agenda, hasLength(1));
        expect(meeting.documents, hasLength(1));
        expect(meeting.participants, hasLength(1));
      },
    );

    test('accepts an agenda item without resolution', () {
      final meeting = unwrap(
        createMeeting(
          _base(agenda: [anAgendaItem(), _plainItem('agenda-2', 2)]),
        ),
      );

      expect(meeting.agenda, hasLength(2));
      expect(findResolution(meeting, aResolutionId()), equals(aResolution()));
    });

    for (final (name, input, field) in <_DuplicateRow>[
      (
        'two agenda items with the same id, neither of them with a resolution',
        _base(agenda: [_plainItem('agenda-1', 1), _plainItem('agenda-1', 2)]),
        ValidationField.agenda,
      ),
      (
        'two agenda items at the same position, '
            'neither of them with a resolution',
        _base(agenda: [_plainItem('agenda-1', 1), _plainItem('agenda-2', 1)]),
        ValidationField.agenda,
      ),
      (
        'two resolutions with the same id, '
            'in items that differ in everything else',
        _base(
          agenda: [
            anAgendaItem(id: anAgendaItemId('agenda-1')),
            anAgendaItem(id: anAgendaItemId('agenda-2'), position: 2),
          ],
        ),
        ValidationField.agenda,
      ),
      (
        'two documents with the same id',
        _base(documents: [aDocument(), aDocument()]),
        ValidationField.documents,
      ),
      (
        'two participants with the same user id',
        _base(participants: [aParticipant(), aParticipant()]),
        ValidationField.participants,
      ),
    ]) {
      test('rejects $name', () {
        expect(
          createMeeting(input),
          equals(err(validationError(field, ValidationRule.duplicate))),
        );
      });
    }

    test('accepts items that differ in id, position and resolution', () {
      expect(
        isOk(
          createMeeting(
            _base(
              agenda: [
                _plainItem('agenda-1', 1),
                _plainItem('agenda-2', 2),
                anAgendaItem(id: anAgendaItemId('agenda-3'), position: 3),
              ],
            ),
          ),
        ),
        isTrue,
      );
    });
  });

  group('findResolution', () {
    final meeting = aMeetingWithAgenda();

    test('finds a resolution in any item of the agenda: '
        'the second item and the third, not only the first', () {
      expect(findResolution(meeting, aResolutionId()), equals(aResolution()));
      expect(
        findResolution(meeting, aResolutionId('resolution-2')),
        isA<Resolution>().having(
          (resolution) => resolution.title,
          'title',
          'Elect the chair',
        ),
      );
    });

    test('finds the only resolution of a single-item agenda', () {
      expect(
        findResolution(aMeeting(), aResolutionId()),
        equals(aResolution()),
      );
    });

    test('returns undefined for an unknown resolution', () {
      expect(findResolution(meeting, aResolutionId('unknown')), isNull);
      expect(findResolution(aMeeting(), aResolutionId('unknown')), isNull);
    });

    test('returns undefined when no item has a resolution', () {
      final empty = unwrap(
        createMeeting(_base(agenda: [_plainItem('agenda-1', 1)])),
      );

      expect(findResolution(empty, aResolutionId()), isNull);
    });
  });

  group('findParticipant', () {
    test('finds a participant by user id', () {
      expect(
        findParticipant(aMeeting(), aUserId('user-2')),
        isA<Participant>().having(
          (participant) => participant.fullName,
          'fullName',
          'Bruno Durand',
        ),
      );
    });

    test('returns undefined for somebody who is not invited', () {
      expect(findParticipant(aMeeting(), aUserId('stranger')), isNull);
    });
  });
}
