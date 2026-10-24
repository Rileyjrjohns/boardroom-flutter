// Flow 2: go offline with the switch of the demo, vote on a meeting already
// seen, see the vote
// saved on the device and waiting to be sent (outcome line, pending votes badge
// and screen), come
// back online, and see the synchronisation: the summary of what was sent, and
// the vote on the
// resolution as recorded. The same scenario and the same test ids as
// `.maestro/offline-vote-resync.yaml` of the React Native app.
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/flows.dart';

/// The second upcoming meeting, its resolution, and the choice the flow casts.
const String _meetingId = 'meeting-002';
const String _resolutionId = 'meeting-002-resolution-subject';
const String _choice = 'against';

void main() {
  patrolTest(
    'offline vote, pending votes, synchronisation',
    config: flowConfig,
    ($) async {
      Future<void> toggleOfflineSwitch() async {
        await byTestId(
          $,
          CoreTestIds.demoOfflineSwitch,
        ).scrollTo(scrollDirection: AxisDirection.up).tap();
      }

      await launchApp($);
      await signIn($);
      await openMeeting($, _meetingId);

      // The meeting is on the screen, hence saved on the device: it can still
      // be read offline.
      final choice = byTestId($, voteChoiceTestId(_resolutionId, _choice));
      await choice.scrollTo();

      // The switch of the demo cuts the simulated network.
      await toggleOfflineSwitch();
      await byTestId($, CoreTestIds.offlineBanner).waitUntilVisible();

      // Offline, the confirmation says the vote will be saved and sent later.
      await choice.scrollTo().tap();
      await byTestId($, VotesTestIds.voteDialog).waitUntilVisible();
      expect(byTestId($, VotesTestIds.voteDialogOffline), findsOneWidget);
      await byTestId($, VotesTestIds.voteConfirm).tap();
      await $.pumpAndTrySettle();
      expect(byTestId($, VotesTestIds.voteDialog), findsNothing);

      // "Waiting to be sent": the outcome says the vote is saved on the device,
      // the choices are
      // gone, and the server has recorded nothing yet, so the resolution does
      // not say "already
      // voted".
      await byTestId($, voteOutcomeTestId(_resolutionId)).scrollTo();
      expect(choice, findsNothing);
      expect(byTestId($, voteNoticeTestId(_resolutionId)), findsNothing);

      // Back on the list, the pending votes button of the header counts the
      // vote, and the screen
      // lists it.
      await goBack($);
      await byTestId($, MeetingsTestIds.meetingsList).waitUntilVisible();
      await byTestId($, VotesTestIds.pendingVotesBadge).waitUntilVisible();
      await byTestId($, VotesTestIds.pendingVotesButton).tap();
      await byTestId($, VotesTestIds.pendingVotesScreen).waitUntilVisible();
      await byTestId($, VotesTestIds.pendingVotesWaiting).waitUntilVisible();
      await byTestId($, pendingVoteTestId(_resolutionId)).waitUntilVisible();
      await goBack($);
      await byTestId($, MeetingsTestIds.meetingsList).waitUntilVisible();

      // The connection comes back: the vote is sent by itself.
      await toggleOfflineSwitch();
      await byTestId($, VotesTestIds.syncSummary).waitUntilVisible();
      expect(byTestId($, CoreTestIds.offlineBanner), findsNothing);

      // Sent: "saved on this device" is no longer true, and the server has the
      // vote: the
      // resolution now says the user has already voted.
      await openMeeting($, _meetingId);
      await byTestId($, voteNoticeTestId(_resolutionId)).scrollTo();
      expect(byTestId($, voteOutcomeTestId(_resolutionId)), findsNothing);
      expect(choice, findsNothing);
    },
  );
}
