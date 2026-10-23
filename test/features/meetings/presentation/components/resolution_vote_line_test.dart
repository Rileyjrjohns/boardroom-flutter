import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/meetings/presentation/components/resolution_vote_line.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/presentation/test_app.dart';

void main() {
  final en = l10nOf();

  group('ResolutionVoteLine', () {
    testWidgets('tells the vote the server recorded', (tester) async {
      await pumpScreen(
        tester,
        ResolutionVoteLine(
          resolution: aResolution(recordedVote: VoteChoice.forChoice),
        ),
      );

      expect(
        find.text(en.meetingsMeetingResolutionYourVote(en.votesVoteChoiceFor)),
        findsOneWidget,
      );
    });

    testWidgets(
      'tells that the user has not voted, when nothing is recorded and '
      'nothing waits',
      (tester) async {
        await pumpScreen(tester, ResolutionVoteLine(resolution: aResolution()));

        expect(find.text(en.meetingsMeetingResolutionNoVote), findsOneWidget);
      },
    );

    testWidgets(
      'tells the vote that waits to be sent, when whoever knows the outbox '
      'says so',
      (tester) async {
        await pumpScreen(
          tester,
          ResolutionVoteLine(
            resolution: aResolution(),
            queuedChoice: VoteChoice.abstain,
          ),
        );

        expect(
          find.text(
            en.meetingsMeetingResolutionYourVoteQueued(
              en.votesVoteChoiceAbstain,
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'says the recorded vote before the one that waits: the server has the '
      'last word',
      (tester) async {
        await pumpScreen(
          tester,
          ResolutionVoteLine(
            resolution: aResolution(recordedVote: VoteChoice.against),
            queuedChoice: VoteChoice.forChoice,
          ),
        );

        expect(
          find.text(
            en.meetingsMeetingResolutionYourVote(en.votesVoteChoiceAgainst),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('waiting'), findsNothing);
      },
    );

    testWidgets(
      'says nothing while the vote is not known: "you have not voted" would '
      'be a guess',
      (tester) async {
        await pumpScreen(
          tester,
          ResolutionVoteLine(resolution: aResolution(), unknown: true),
        );

        expect(find.textContaining('voted'), findsNothing);
      },
    );
  });
}
