// Flow 1: a reader signs in, sees the meetings, leaves the app for longer than
// the grace period,
// unlocks it with the biometrics, opens a meeting and reads its confidential
// report (protected
// badge, PDF view). The same scenario and the same test ids as
// `.maestro/biometric-login-list-document.yaml` of the React Native app.
//
// The biometrics: on a simulator or an emulator with nothing enrolled, the
// development
// configuration uses the simulated gate (it always recognises the user), so the
// lock screen offers
// the unlock button and a tap on it succeeds with no system prompt. With a
// fingerprint or a face
// enrolled the system prompt would be shown, and this flow cannot answer it.
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/features/documents/presentation/test_ids.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/flows.dart';

/// The grace period of the app lock is 30 seconds (`appLockGracePeriod` in
/// `lib/app/composition/settings.dart`); the app stays in the background a
/// little longer.
const Duration _timeInBackground = Duration(seconds: 35);

/// The first upcoming meeting, and the id of its confidential report.
const String _meetingId = 'meeting-001';
const String _confidentialDocumentId = 'meeting-001-document-2';

void main() {
  patrolTest(
    'biometric login, meetings list, confidential document',
    config: flowConfig,
    timeout: flowTimeout,
    ($) async {
      await launchApp($);
      await signIn($);

      // Leave the app for longer than the grace period, then come back.
      await leaveAppFor($, _timeInBackground);

      // The app is locked: the lock screen is shown, nothing of the signed-in
      // user is behind it.
      await byTestId($, AuthTestIds.lockScreen).waitUntilVisible();
      expect(byTestId($, MeetingsTestIds.meetingsList), findsNothing);

      // The biometric unlock (simulated when nothing is enrolled) gives the
      // meetings back.
      await byTestId($, AuthTestIds.lockUnlock).tap();
      await byTestId($, MeetingsTestIds.meetingsList).waitUntilVisible();
      expect(byTestId($, AuthTestIds.lockScreen), findsNothing);

      // From the list to the meeting, then to its confidential document.
      await openMeeting($, _meetingId);
      await byTestId(
        $,
        documentTestId(_confidentialDocumentId),
      ).scrollTo().tap();
      await byTestId($, DocumentsTestIds.documentScreen).waitUntilVisible();

      // The document is confidential: the badge says the screen is protected,
      // and the PDF is
      // drawn.
      expect(
        byTestId($, DocumentsTestIds.documentProtectedBadge),
        findsOneWidget,
      );
      await byTestId($, DocumentsTestIds.documentPdf).waitUntilVisible();
      expect(byTestId($, DocumentsTestIds.documentPdfError), findsNothing);
    },
  );
}
