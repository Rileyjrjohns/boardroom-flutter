// CAPTURE FLOW, NOT A TEST: it drives the app through the scenario of the
// README media (docs/media) and asserts nothing beyond what it waits for. It
// lives in tool/media/, not in integration_test/, so that `patrol test` (which
// runs every file of integration_test/, and so does the end-to-end workflow)
// never runs it.
//
// Run it with `tool/media/capture.sh`, which also records the screen, takes the
// screenshots and converts them. The flow tells the script when to act by
// a Patrol step named `media`: `start` and `end` frame the video, `shot <name>`
// asks for a screenshot of the screen as it is (taken by `simctl`,
// because XCTest leaves the secure content of iOS out of its screenshots: the
// password field and the pages of a protected document).
//
// The scenario: sign in with the demo account, the meetings list, a meeting, a
// vote cast while offline (the switch of the demo) and waiting to be sent, back
// online and the vote sent, then a confidential document with its watermark and
// its protected screen badge.
import 'package:boardroom/app/app.dart';
import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/app/container/create_container.dart';
import 'package:boardroom/app/container/runtime.dart';
import 'package:boardroom/core/infrastructure/monitoring/console_monitoring.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/features/documents/infrastructure/native/native_screen_protection.dart';
import 'package:boardroom/features/documents/infrastructure/native/pigeon_screen_protection_module.dart';
import 'package:boardroom/features/documents/presentation/test_ids.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:patrol/patrol.dart';

import '../../integration_test/support/flows.dart';

const String _meetingId = 'meeting-002';
const String _resolutionId = 'meeting-002-resolution-subject';
const String _choice = 'for';
const String _documentId = 'meeting-002-document-2';

/// Lets a screen settle before it is photographed, and gives the viewer of the
/// GIF time to read it.
Future<void> _pause([int milliseconds = 1200]) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// Writes a step called `media` in the output of Patrol (which shows no other
/// print of the app), and holds still for a moment so that the script, which
/// reads that output, can act while the screen is unchanged.
Future<void> _mark(PatrolIntegrationTester $, String command) =>
    $.wrapWithPatrolLog(
      action: 'media',
      value: command,
      color: '',
      function: () => Future<void>.delayed(const Duration(milliseconds: 700)),
    );

/// Starts the app the way `main` does, with three differences that only matter
/// for a picture. The language is English whatever the language the test runner
/// gives the app. The ribbon "DEBUG" that Flutter draws on a debug build (a
/// simulator cannot run a release build) is covered by a patch of the colour of
/// the top bar, over the corner of the status bar where nothing else is. (The
/// name of the test, which Patrol writes in red at the top of the screen, is
/// switched off by `capture.sh` with --no-label.)
Future<void> _launchForCapture(PatrolIntegrationTester $) async {
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          BoardroomApp(
            locale: const Locale('en'),
            start: (promptText) => startContainer(
              const RawSettings.fromEnvironment(),
              ContainerRuntime(
                biometricPromptText: promptText,
                screenProtection: NativeScreenProtection(
                  module: loadScreenProtectionModule(),
                  monitoring: const ConsoleMonitoring(),
                ),
              ),
              development: kDebugMode,
            ),
          ),
          const Positioned(
            top: 0,
            right: 0,
            width: 80,
            height: 58,
            child: ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ],
      ),
    ),
  );
  await byTestId($, AuthTestIds.signInScreen).waitUntilVisible();
}

void main() {
  patrolTest(
    'capture the media of the README',
    config: flowConfig,
    timeout: flowTimeout,
    ($) async {
      await _launchForCapture($);
      await $.pumpAndTrySettle();
      await _pause(500);
      await _mark($, 'start');
      await _pause(800);

      // 1. Sign in with the demo account.
      await byTestId($, demoAccountTestId(demoAccountEmail)).tap();
      await $.pumpAndTrySettle();
      await _mark($, 'shot sign-in');
      await _pause(1500);
      await byTestId($, AuthTestIds.signInSubmit).tap();

      // 2. The meetings list.
      await byTestId($, MeetingsTestIds.meetingsList).waitUntilVisible();
      await $.pumpAndTrySettle();
      await _pause();

      // 3. A meeting, with a resolution to vote on.
      await openMeeting($, _meetingId);
      await $.pumpAndTrySettle();
      await _mark($, 'shot meeting');
      await _pause();

      // 4. Offline: cut the simulated network, then vote. The vote is saved on
      // the device and waits to be sent.
      await byTestId($, CoreTestIds.demoOfflineSwitch).tap();
      await byTestId($, CoreTestIds.offlineBanner).waitUntilVisible();
      await $.pumpAndTrySettle();
      final choice = byTestId($, voteChoiceTestId(_resolutionId, _choice));
      await choice.scrollTo();
      await $.pumpAndTrySettle();
      await _pause(800);
      await choice.tap();
      await byTestId($, VotesTestIds.voteDialog).waitUntilVisible();
      await $.pumpAndTrySettle();
      await _pause(1000);
      await byTestId($, VotesTestIds.voteConfirm).tap();
      await $.pumpAndTrySettle();
      await byTestId($, voteOutcomeTestId(_resolutionId)).scrollTo();
      await $.pumpAndTrySettle();
      await _mark($, 'shot offline-vote');
      await _pause(1500);

      // 5. Back online: the vote is sent, and the app says so.
      await byTestId(
        $,
        CoreTestIds.demoOfflineSwitch,
      ).scrollTo(scrollDirection: AxisDirection.up).tap();
      await byTestId($, VotesTestIds.syncSummary).waitUntilVisible();
      await $.pumpAndTrySettle();
      await _pause(1800);
      await byTestId($, VotesTestIds.syncSummaryDismiss).tap();
      await $.pumpAndTrySettle();

      // 6. A confidential document of the same meeting, with its protected
      // screen badge and the watermark over the PDF.
      await byTestId($, documentTestId(_documentId)).scrollTo().tap();
      await byTestId(
        $,
        DocumentsTestIds.documentProtectedBadge,
      ).waitUntilVisible();
      await byTestId($, DocumentsTestIds.documentPdf).waitUntilVisible();
      await $.pumpAndTrySettle();
      await _pause(1500);
      await _mark($, 'shot protected-document');
      await _pause(2500);
      await _mark($, 'end');
    },
  );
}
