import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/presentation/components/capture_notice.dart';
import 'package:boardroom/features/documents/presentation/state/capture_watch.dart';
import 'package:boardroom/features/documents/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/presentation/test_app.dart';

CaptureNoticeValue _notice(ScreenCaptureKind kind, int sequence) =>
    CaptureNoticeValue(kind: kind, sequence: sequence);

Widget _host(
  CaptureNoticeValue notice,
  VoidCallback onDismiss,
  Locale locale,
) => testHost(
  ProviderContainer(),
  CaptureNotice(notice: notice, onDismiss: onDismiss),
  locale: locale,
);

void main() {
  group('CaptureNotice', () {
    testWidgets('says a screenshot was seen, and that it was recorded', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _notice(ScreenCaptureKind.screenshotTaken, 1),
          () {},
          const Locale('en'),
        ),
      );

      expect(
        find.descendant(
          of: byTestId(DocumentsTestIds.documentCaptureNotice),
          matching: find.text(l10nOf().documentsDocumentCaptureScreenshot),
        ),
        findsOneWidget,
      );
    });

    testWidgets('says a recording was seen, in French', (tester) async {
      const fr = Locale('fr');
      await tester.pumpWidget(
        _host(_notice(ScreenCaptureKind.recordingStarted, 1), () {}, fr),
      );

      expect(
        find.text(l10nOf(fr).documentsDocumentCaptureRecording),
        findsOneWidget,
      );
    });

    testWidgets('is a new live region for each notice, whatever the words', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _notice(ScreenCaptureKind.screenshotTaken, 1),
          () {},
          const Locale('en'),
        ),
      );
      final first = tester.widget<LiveText>(find.byType(LiveText)).key;

      await tester.pumpWidget(
        _host(
          _notice(ScreenCaptureKind.screenshotTaken, 2),
          () {},
          const Locale('en'),
        ),
      );

      expect(tester.widget<LiveText>(find.byType(LiveText)).key, isNot(first));
    });

    testWidgets('has a dismiss button that tells the screen', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        _host(
          _notice(ScreenCaptureKind.screenshotTaken, 1),
          () => dismissed += 1,
          const Locale('en'),
        ),
      );

      await tester.tap(byTestId(DocumentsTestIds.documentCaptureDismiss));

      expect(dismissed, 1);
      expect(find.text(l10nOf().coreBannerDismiss), findsOneWidget);
    });
  });
}
