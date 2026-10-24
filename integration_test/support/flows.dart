// The steps both end-to-end flows share, written once. The test ids are the
// ones of
// docs/spec/screens.md (the same as the Maestro flows of the React Native app),
// taken from
// the constants of the app so that a renamed id breaks the build and not just
// the run.
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:patrol/patrol.dart';

/// The demo account every flow signs in with: the first one of the fixtures,
/// Alice Martin, a
/// voting member of most meetings.
const String demoAccountEmail = 'alice.martin@boardroom.example';

/// How long the app waits for a screen before a step fails. The first build of
/// the app on a
/// slow emulator and the simulated latency make the default of 10 seconds too
/// tight.
const Duration screenTimeout = Duration(seconds: 30);

/// The settings of every flow: Patrol's finders wait this long for a widget to
/// appear.
const PatrolTesterConfig flowConfig = PatrolTesterConfig(
  existsTimeout: screenTimeout,
  visibleTimeout: screenTimeout,
  settleTimeout: Duration(seconds: 5),
);

/// The finder of a widget by its test id (the `Key` the app gives it).
PatrolFinder byTestId(PatrolIntegrationTester $, String id) => $(Key(id));

/// Starts the app (the development configuration, whose fixtures are served in
/// process) on the
/// sign-in screen.
Future<void> launchApp(PatrolIntegrationTester $) async {
  app.main();
  await byTestId($, AuthTestIds.signInScreen).waitUntilVisible();
}

/// Signs in with the demo account and waits for the meetings list.
Future<void> signIn(PatrolIntegrationTester $) async {
  await byTestId($, demoAccountTestId(demoAccountEmail)).tap();
  await byTestId($, AuthTestIds.signInSubmit).tap();
  await byTestId($, MeetingsTestIds.meetingsList).waitUntilVisible();
}

/// Opens a meeting from the list and waits for its detail.
Future<void> openMeeting(PatrolIntegrationTester $, String meetingId) async {
  await byTestId($, meetingRowTestId(meetingId)).scrollTo().tap();
  await byTestId($, MeetingsTestIds.meetingDetail).waitUntilVisible();
}

/// Goes back one screen with the back button of the header (the app bar puts
/// one on every screen
/// that is not the first of the stack).
Future<void> goBack(PatrolIntegrationTester $) async {
  await $(BackButton).tap();
  await $.pumpAndTrySettle();
}
