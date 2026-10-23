import 'package:boardroom/features/meetings/domain/entities/agenda_item.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/domain/with_vote_recorded.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';

// The scenarios of `withVoteRecorded` are in `Meeting.test.ts` in React Native,
// where the function is in the module of the meeting. In Dart it belongs to the
// votes, which depend on the meetings and not the other way round (see
// docs/architecture.md), so they are in this file, and `tool/scenario_parity.dart`
// reads them for `Meeting.test.ts` (`splitScenarioFiles`).

MeetingInput _base({List<AgendaItem> agenda = const []}) => MeetingInput(
  summary: aMeetingSummary(),
  agenda: agenda,
  documents: const [],
  participants: const [],
);

void main() {
  group('withVoteRecorded', () {
    final vote = aVote(choice: VoteChoice.against);

    test(
      'returns a copy in which the resolution carries the choice of the vote',
      () {
        final meeting = aMeeting();

        final updated = withVoteRecorded(meeting, vote);

        expect(
          findResolution(updated, aResolutionId()),
          isA<Resolution>().having(
            (resolution) => resolution.recordedVote,
            'recordedVote',
            VoteChoice.against,
          ),
        );
        expect(
          updated,
          equals(
            meeting.copyWith(
              agenda: [
                meeting.agenda[0].copyWith(
                  resolution: aResolution().copyWith(
                    recordedVote: VoteChoice.against,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    test('leaves the original meeting untouched', () {
      final meeting = aMeeting();

      withVoteRecorded(meeting, vote);

      expect(
        findResolution(meeting, aResolutionId()),
        isA<Resolution>().having(
          (resolution) => resolution.recordedVote,
          'recordedVote',
          isNull,
        ),
      );
    });

    test('only changes the resolution of the vote', () {
      final other = anAgendaItem(
        id: anAgendaItemId('agenda-2'),
        position: 2,
        resolution: aResolution(id: aResolutionId('resolution-2')),
      );
      final meeting = unwrap(
        createMeeting(_base(agenda: [anAgendaItem(), other])),
      );

      final updated = withVoteRecorded(meeting, vote);

      expect(
        findResolution(updated, aResolutionId('resolution-2')),
        isA<Resolution>().having(
          (resolution) => resolution.recordedVote,
          'recordedVote',
          isNull,
        ),
      );
      expect(updated.agenda[1], same(meeting.agenda[1]));
    });

    test('records the vote on a resolution that is not in the first item '
        'of the agenda', () {
      final meeting = aMeetingWithAgenda();

      final updated = withVoteRecorded(
        meeting,
        aVote(
          resolutionId: aResolutionId('resolution-2'),
          choice: VoteChoice.abstain,
        ),
      );

      expect(
        findResolution(updated, aResolutionId('resolution-2')),
        isA<Resolution>().having(
          (resolution) => resolution.recordedVote,
          'recordedVote',
          VoteChoice.abstain,
        ),
      );
      expect(
        findResolution(updated, aResolutionId()),
        isA<Resolution>().having(
          (resolution) => resolution.recordedVote,
          'recordedVote',
          isNull,
        ),
      );
      expect(updated.agenda[0], same(meeting.agenda[0]));
      expect(updated.agenda[1], same(meeting.agenda[1]));
    });

    test('returns the meeting unchanged for a vote of another meeting', () {
      final meeting = aMeeting();

      expect(
        withVoteRecorded(meeting, aVote(meetingId: aMeetingId('other'))),
        same(meeting),
      );
    });

    test('returns an equal meeting for a resolution it does not have', () {
      final meeting = aMeeting();

      expect(
        withVoteRecorded(
          meeting,
          aVote(resolutionId: aResolutionId('missing')),
        ),
        equals(meeting),
      );
    });
  });
}
