import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/policies/voting_state.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/meetings/presentation/messages.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/presentation/test_app.dart';

// Where a code of the meetings becomes a text. The scenarios are the ones of
// meetingMessageKeys.test.ts of the React Native app; the exhaustiveness of
// each switch is checked by the analyzer instead of the typecheck.

void main() {
  group('the maps from codes to translation keys', () {
    test('translates a code the way the screens do', () {
      final en = l10nOf();

      expect(
        participantRoleLabel(en, ParticipantRole.chair),
        en.meetingsParticipantRoleChair,
      );
      expect(
        votingStateLabel(en, VotingState.windowOver),
        en.meetingsVotingStateWindowOver,
      );
      expect(
        votingDateLabel(en, VotingState.open, 'D'),
        en.meetingsMeetingVotingDeadline('D'),
      );
      expect(
        votingDateLabel(en, VotingState.closed, 'D'),
        en.meetingsMeetingVotingClosedOn('D'),
      );
      expect(
        votingDateLabel(en, VotingState.windowOver, 'D'),
        en.meetingsMeetingVotingClosedOn('D'),
      );
      expect(
        confidentialityLabel(en, ConfidentialityLevel.confidential),
        en.meetingsConfidentialityConfidential,
      );
      expect(voteChoiceLabel(en, VoteChoice.forChoice), en.votesVoteChoiceFor);
      expect(meetingPeriodLabel(en, MeetingPeriod.past), en.meetingsPeriodPast);
      expect(emptyListLabel(en, MeetingPeriod.past), en.meetingsEmptyPast);
    });

    test('has a text in every language for every code', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final texts = l10nOf(locale);
        final all = [
          for (final role in ParticipantRole.values)
            participantRoleLabel(texts, role),
          for (final state in VotingState.values)
            votingStateLabel(texts, state),
          for (final state in VotingState.values)
            votingDateLabel(texts, state, 'D'),
          for (final level in ConfidentialityLevel.values)
            confidentialityLabel(texts, level),
          for (final choice in VoteChoice.values)
            voteChoiceLabel(texts, choice),
          for (final period in MeetingPeriod.values) ...[
            meetingPeriodLabel(texts, period),
            emptyListLabel(texts, period),
          ],
        ];

        expect(all, everyElement(isNotEmpty));
      }
    });
  });
}
