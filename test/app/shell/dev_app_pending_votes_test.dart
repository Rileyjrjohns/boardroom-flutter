import 'package:boardroom/app/app.dart';
import 'package:boardroom/app/container/app_container.dart';
import 'package:boardroom/app/container/create_container.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/presentation/test_app.dart';
import '../container/container_support.dart';

// The whole app in the development configuration, as `main` starts it: the
// container is the one `createContainer` builds (the real HTTP adapters over
// the fixture server, the outbox and the caches in memory), mounted in the real
// `BoardroomApp`. These tests follow a vote from the resolution to the pending
// votes screen, to settle whether a vote cast offline shows there.

/// The meeting and the resolution the tests vote on: the first open one the
/// first account has not voted on yet. The fixtures are the same in every
/// container, so the ids found in one hold in another.
Future<({Meeting meeting, Resolution resolution})> _target(
  WidgetTester tester,
) async {
  final probe = await tester.runAsync(aDevContainer);
  final target = await tester.runAsync(
    () => anOpenResolution(probe!.container),
  );
  return target!;
}

/// Mounts the app on a development container that starts signed out, and signs
/// the first demo account in through the screen.
Future<AppContainer> _pumpSignedIn(WidgetTester tester) async {
  final world = silentRuntime();
  final created = await tester.runAsync(
    () => createContainer(dev(startSignedIn: false), world.runtime),
  );
  final container = built(created!);
  addTearDown(container.dispose);
  await tester.pumpWidget(BoardroomApp(start: (_) async => created));
  await _settle(tester);
  expect(byTestId(AuthTestIds.signInScreen), findsOneWidget);

  await _tap(tester, byTestId(demoAccountTestId(aliceEmail)));
  await _tap(tester, byTestId(AuthTestIds.signInSubmit));
  expect(byTestId(MeetingsTestIds.meetingsList), findsOneWidget);
  return container;
}

/// Lets the app settle. The container works on real futures (the fixture server
/// answers through the event loop), so the event queue is drained outside the
/// fake clock between the frames.
Future<void> _settle(WidgetTester tester) async {
  for (var round = 0; round < 20; round++) {
    await tester.runAsync(pumpEventQueue);
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _settle(tester);
}

/// Opens the meeting of [target]. A meeting that was never loaded cannot be
/// opened offline, so a test that goes offline does it from the meeting.
Future<void> _openMeeting(
  WidgetTester tester,
  ({Meeting meeting, Resolution resolution}) target,
) async {
  final row = byTestId(meetingRowTestId(target.meeting.id));
  await tester.scrollUntilVisible(
    row,
    200,
    scrollable: find.descendant(
      of: byTestId(MeetingsTestIds.meetingsList),
      matching: find.byType(Scrollable),
    ),
  );
  await _tap(tester, row);
}

/// Casts [VoteChoice.forChoice] on the resolution of the open meeting, with the
/// biometrics succeeding.
Future<void> _castVote(
  WidgetTester tester,
  ({Meeting meeting, Resolution resolution}) target,
) async {
  final resolutionId = target.resolution.id;
  await _tap(
    tester,
    byTestId(voteChoiceTestId(resolutionId, VoteChoice.forChoice.value)),
  );
  await _tap(tester, byTestId(VotesTestIds.voteConfirm));
  await _settle(tester);
}

void main() {
  final en = l10nOf();

  testWidgets('a vote cast offline is listed in the pending votes, sent when '
      'the network is back, and the list empties', (tester) async {
    final target = await _target(tester);
    final container = await _pumpSignedIn(tester);
    final network = container.demoControls!.network;

    await _openMeeting(tester, target);
    await _tap(tester, byTestId(CoreTestIds.demoOfflineSwitch));
    expect(network.online, isFalse);

    await _castVote(tester, target);
    expect(byTestId(VotesTestIds.voteDialog), findsNothing);

    await tester.pageBack();
    await _settle(tester);
    expect(byTestId(VotesTestIds.pendingVotesBadge), findsOneWidget);

    await _tap(tester, byTestId(VotesTestIds.pendingVotesButton));
    expect(byTestId(VotesTestIds.pendingVotesScreen), findsOneWidget);
    expect(byTestId(VotesTestIds.pendingVotesWaiting), findsOneWidget);
    expect(byTestId(pendingVoteTestId(target.resolution.id)), findsOneWidget);
    expect(byTestId(VotesTestIds.pendingVotesEmpty), findsNothing);

    await _tap(tester, byTestId(CoreTestIds.demoOfflineSwitch));
    await _settle(tester);

    expect(network.online, isTrue);
    expect(byTestId(VotesTestIds.pendingVotesEmpty), findsOneWidget);
    expect(byTestId(VotesTestIds.pendingVotesWaiting), findsNothing);
    expect(byTestId(VotesTestIds.syncSummary), findsOneWidget);
    expect(find.text(en.votesBannerSent(1)), findsOneWidget);
  });

  testWidgets('a vote cast online is sent at once, so the pending votes stay '
      'empty', (tester) async {
    final target = await _target(tester);
    final container = await _pumpSignedIn(tester);
    expect(container.demoControls!.network.online, isTrue);

    await _openMeeting(tester, target);
    await _castVote(tester, target);
    await tester.pageBack();
    await _settle(tester);
    expect(byTestId(VotesTestIds.pendingVotesBadge), findsNothing);

    await _tap(tester, byTestId(VotesTestIds.pendingVotesButton));

    expect(byTestId(VotesTestIds.pendingVotesEmpty), findsOneWidget);
    expect(byTestId(VotesTestIds.pendingVotesWaiting), findsNothing);
  });
}
