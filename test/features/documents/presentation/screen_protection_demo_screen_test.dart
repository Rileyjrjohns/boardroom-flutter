import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/features/documents/presentation/screen_protection_demo_screen.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes/fake_screen_protection.dart';

const _screenshot = ScreenCaptureEvent(kind: ScreenCaptureKind.screenshotTaken);
const _started = ScreenCaptureEvent(kind: ScreenCaptureKind.recordingStarted);
const _stopped = ScreenCaptureEvent(kind: ScreenCaptureKind.recordingStopped);

void main() {
  Future<AppLocalizations> pump(
    WidgetTester tester,
    FakeScreenProtection protection, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScreenProtectionDemoScreen(screenProtection: protection),
      ),
    );
    return lookupAppLocalizations(locale);
  }

  Finder switchFinder() => find.byType(Switch);

  testWidgets(
    'starts with the protection off, the sample text and no capture',
    (tester) async {
      final protection = FakeScreenProtection();
      final l10n = await pump(tester, protection);

      expect(tester.widget<Switch>(switchFinder()).value, isFalse);
      expect(find.text(l10n.screenProtectionDemoConfidential), findsOneWidget);
      expect(find.text(l10n.screenProtectionDemoEventsEmpty), findsOneWidget);
      expect(protection.enableCalls, equals(0));
    },
  );

  testWidgets('turns the protection on and off with the switch', (
    tester,
  ) async {
    final protection = FakeScreenProtection();
    await pump(tester, protection);

    await tester.tap(switchFinder());
    await tester.pump();
    expect(protection.enabled, isTrue);
    expect(tester.widget<Switch>(switchFinder()).value, isTrue);

    await tester.tap(switchFinder());
    await tester.pump();
    expect(protection.enabled, isFalse);
    expect(tester.widget<Switch>(switchFinder()).value, isFalse);
  });

  testWidgets('lists the captures the system reports, in order', (
    tester,
  ) async {
    final protection = FakeScreenProtection();
    final l10n = await pump(tester, protection);

    protection
      ..emit(_screenshot)
      ..emit(_started)
      ..emit(_stopped);
    await tester.pump();

    expect(find.text(l10n.screenProtectionDemoEventsEmpty), findsNothing);
    final tops = [
      for (final text in [
        l10n.screenProtectionDemoScreenshot,
        l10n.screenProtectionDemoRecordingStarted,
        l10n.screenProtectionDemoRecordingStopped,
      ])
        tester.getTopLeft(find.text(text)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(tops.toSet(), hasLength(3));
  });

  for (final (name, failure, text)
      in <(String, ScreenProtectionError, String Function(AppLocalizations))>[
        (
          'unsupported',
          screenProtectionUnsupported(),
          (l10n) => l10n.screenProtectionDemoErrorUnsupported,
        ),
        (
          'failed',
          screenProtectionFailed(),
          (l10n) => l10n.screenProtectionDemoErrorFailed,
        ),
      ]) {
    testWidgets('says so when the protection cannot be turned on ($name), '
        'and the switch stays off', (tester) async {
      final protection = FakeScreenProtection()..enableFailure = failure;
      final l10n = await pump(tester, protection);

      await tester.tap(switchFinder());
      await tester.pump();

      expect(find.text(text(l10n)), findsOneWidget);
      expect(tester.widget<Switch>(switchFinder()).value, isFalse);
    });
  }

  testWidgets('shows the texts in French', (tester) async {
    final protection = FakeScreenProtection();
    final l10n = await pump(tester, protection, locale: const Locale('fr'));

    expect(find.text(l10n.screenProtectionDemoTitle), findsOneWidget);
    expect(find.text(l10n.screenProtectionDemoSwitch), findsOneWidget);
    expect(
      l10n.screenProtectionDemoSwitch,
      isNot(
        lookupAppLocalizations(const Locale('en')).screenProtectionDemoSwitch,
      ),
    );
  });

  testWidgets('turns the protection off and stops listening when it is left', (
    tester,
  ) async {
    final protection = FakeScreenProtection();
    await pump(tester, protection);
    await tester.tap(switchFinder());
    await tester.pump();
    expect(protection.listenerCount, equals(1));

    await tester.pumpWidget(const SizedBox());

    expect(protection.disableCalls, equals(1));
    expect(protection.enabled, isFalse);
    expect(protection.listenerCount, equals(0));
  });

  testWidgets('leaves the protection alone when it was never turned on', (
    tester,
  ) async {
    final protection = FakeScreenProtection();
    await pump(tester, protection);

    await tester.pumpWidget(const SizedBox());

    expect(protection.disableCalls, equals(0));
  });
}
