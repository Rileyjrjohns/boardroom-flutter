import 'dart:async';

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/auth/domain/entities/user.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/features/documents/presentation/screens/document_screen.dart';
import 'package:boardroom/features/documents/presentation/test_ids.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/fakes/create_fakes.dart';
import '../../../../support/presentation/test_app.dart';
import '../fake_pdf_views.dart';

// The screen of a document, with the real providers, the real use cases over
// the fakes of the ports and the real translations. The PDF view is the fake of
// `fake_pdf_views.dart`, driven by hand.

final User _reader = aUser();
final Document _report = aConfidentialDocument(
  id: aDocumentId('report'),
  title: 'Remuneration report',
  pageCount: 12,
);
final Document _pack = aDocument(id: aDocumentId('pack'), title: 'Board pack');
final Document _minutes = aDocument(
  id: aDocumentId('minutes'),
  title: 'Minutes',
  confidentiality: ConfidentialityLevel.public,
  pageCount: 2,
);

String _locationOf(String id) => 'file:///documents/$id.pdf';

Fakes _aWorld() {
  final fakes = createFakes();
  for (final document in [_report, _pack, _minutes]) {
    fakes.documents.addDocument(
      document,
      aDocumentLocation(_locationOf(document.id)),
    );
  }
  return fakes;
}

/// What a test holds of a screen it mounted.
class _Rendered {
  const new(this.fakes, this.providers, this.pdf);

  final Fakes fakes;
  final ProviderContainer providers;
  final FakePdfViews pdf;
}

Future<_Rendered> _render(
  WidgetTester tester, {
  String? documentId,
  Fakes? fakes,
  Locale locale = const Locale('en'),
}) async {
  final world = fakes ?? _aWorld();
  final pdf = FakePdfViews();
  final providers = await pumpScreen(
    tester,
    DocumentScreen(documentId: documentId ?? _report.id),
    app: TestApp(fakes: world),
    locale: locale,
    extra: [pdf.override],
  );
  return _Rendered(world, providers, pdf);
}

/// Lets the document open: the use cases answer through microtasks.
Future<void> _settle(WidgetTester tester) async {
  for (var round = 0; round < 5; round += 1) {
    await tester.pump();
  }
}

/// Waits until the document is open and the file is handed to the PDF view.
Future<void> _opened(WidgetTester tester) async {
  await _settle(tester);
  expect(byTestId(DocumentsTestIds.documentPdf), findsOneWidget);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
}

String _tileText() =>
    (byTestId(DocumentsTestIds.documentWatermarkTile).evaluate().first.widget
            as Text)
        .data!;

String _tileTextOf(String id) =>
    (find
                .descendant(of: byTestId(id), matching: find.byType(Text))
                .evaluate()
                .first
                .widget
            as Text)
        .data!;

void main() {
  late AppLocalizations en;

  setUp(() => en = l10nOf());

  group('DocumentScreen, a confidential document', () {
    testWidgets(
      'turns the screen protection on, shows the file in the PDF view and '
      'says the screen is protected',
      (tester) async {
        final r = await _render(tester);
        expect(byTestId(DocumentsTestIds.documentLoading), findsOneWidget);

        await _opened(tester);

        expect(r.fakes.screenProtection.enabled, isTrue);
        expect(r.pdf.request.location, _locationOf('report'));
        expect(
          find.descendant(
            of: byTestId(DocumentsTestIds.documentProtectedBadge),
            matching: find.text(en.documentsDocumentProtectedBadge),
          ),
          findsOneWidget,
        );
        expect(find.text('Remuneration report'), findsOneWidget);
        expect(byTestId(DocumentsTestIds.documentLoading), findsNothing);
      },
    );

    testWidgets(
      'draws the name and the email of the reader and the time of the '
      'opening over the file',
      (tester) async {
        await _render(tester);
        await _opened(tester);

        final tiles = find.byKey(
          const Key(DocumentsTestIds.documentWatermarkTile),
        );

        expect(tiles.evaluate().length, greaterThan(10));
        final expected = [
          _reader.fullName,
          _reader.email,
          Formatters('en').dateTime(now),
        ].join('\n');
        for (final tile in tiles.evaluate()) {
          expect((tile.widget as Text).data, expected);
        }
      },
    );

    testWidgets(
      'keeps the watermark out of the way of the touch and of the screen '
      'reader',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await _render(tester);
        await _opened(tester);

        final watermark = byTestId(DocumentsTestIds.documentWatermark);
        expect(
          tester
              .widget<IgnorePointer>(
                find.descendant(
                  of: watermark,
                  matching: find.byType(IgnorePointer),
                ),
              )
              .ignoring,
          isTrue,
        );
        expect(
          tester
              .widget<ExcludeSemantics>(
                find.descendant(
                  of: watermark,
                  matching: find.byType(ExcludeSemantics),
                ),
              )
              .excluding,
          isTrue,
        );
        expect(find.bySemanticsLabel(RegExp(_reader.fullName)), findsNothing);
        semantics.dispose();
      },
    );

    testWidgets('releases the screen when the user goes back, once', (
      tester,
    ) async {
      final r = await _render(tester);
      await _opened(tester);

      await _unmount(tester);

      expect(r.fakes.screenProtection.enabled, isFalse);
      expect(r.fakes.screenProtection.enableCalls, 1);
      expect(r.fakes.screenProtection.disableCalls, 1);
    });

    testWidgets(
      'writes the opening in the logs with the identifiers of the document '
      'and the reader, and nothing else',
      (tester) async {
        final r = await _render(tester);
        await _opened(tester);

        final opening = r.fakes.monitoring.logs.firstWhere(
          (record) => record.event == MonitoringEvent.documentOpened,
        );

        expect(opening.attributes![LogAttribute.documentId], 'report');
        expect(opening.attributes![LogAttribute.userId], _reader.id);
        final logged = r.fakes.monitoring.logs.toString();
        for (final secret in [
          _reader.fullName,
          _reader.email,
          'Remuneration',
        ]) {
          expect(logged, isNot(contains(secret)));
        }
      },
    );
  });

  group('DocumentScreen, the secure container', () {
    testWidgets(
      'puts the PDF and the watermark of a protected document in the secure '
      'container, and the title and the badge outside it',
      (tester) async {
        await _render(tester);
        await _opened(tester);

        final container = byTestId(DocumentsTestIds.documentSecureContent);
        expect(container, findsOneWidget);
        Finder inside(String id) =>
            find.descendant(of: container, matching: byTestId(id));
        expect(inside(DocumentsTestIds.documentPdf), findsOneWidget);
        expect(inside(DocumentsTestIds.documentWatermark), findsOneWidget);
        expect(inside(DocumentsTestIds.documentTitle), findsNothing);
        expect(inside(DocumentsTestIds.documentProtectedBadge), findsNothing);
        expect(
          byTestId(DocumentsTestIds.documentProtectedBadge),
          findsOneWidget,
        );
      },
    );

    for (final document in [_pack, _minutes]) {
      testWidgets(
        'keeps the container plain for a document that is not protected: '
        '${document.title}',
        (tester) async {
          await _render(tester, documentId: document.id);
          await _opened(tester);

          final container = byTestId(DocumentsTestIds.documentSecureContent);
          expect(container, findsOneWidget);
          expect(
            find.descendant(
              of: container,
              matching: byTestId(DocumentsTestIds.documentPdf),
            ),
            findsOneWidget,
          );
        },
      );
    }
  });

  group('DocumentScreen, a document that is not confidential', () {
    for (final document in [_pack, _minutes]) {
      testWidgets(
        'leaves the screen unprotected, with no badge, and carries the '
        'watermark all the same: ${document.title}',
        (tester) async {
          final r = await _render(tester, documentId: document.id);
          await _opened(tester);

          expect(r.fakes.screenProtection.enabled, isFalse);
          expect(r.fakes.screenProtection.enableCalls, 0);
          expect(
            byTestId(DocumentsTestIds.documentProtectedBadge),
            findsNothing,
          );
          // Every document viewed carries the name of the reader: it deters a
          // photograph of any of them.
          expect(
            find
                .byKey(const Key(DocumentsTestIds.documentWatermarkTile))
                .evaluate()
                .length,
            greaterThan(10),
          );
          expect(_tileText(), contains(_reader.fullName));
          expect(_tileText(), contains(_reader.email));
          expect(find.text(document.title), findsOneWidget);

          await _unmount(tester);
          expect(r.fakes.screenProtection.disableCalls, 0);
        },
      );
    }
  });

  group('DocumentScreen, the PDF view', () {
    testWidgets(
      'shows a loading state until the file is read, then the page the '
      'reader is on',
      (tester) async {
        final r = await _render(tester);
        await _opened(tester);
        expect(byTestId(DocumentsTestIds.documentPdfLoading), findsOneWidget);
        expect(byTestId(DocumentsTestIds.documentPageIndicator), findsNothing);

        r.pdf.request.onLoaded(12);
        await tester.pump();

        expect(byTestId(DocumentsTestIds.documentPdfLoading), findsNothing);
        expect(
          tester
              .widget<Text>(byTestId(DocumentsTestIds.documentPageIndicator))
              .data,
          en.documentsDocumentPageIndicator('1', '12'),
        );

        r.pdf.request.onPageChanged(7, 12);
        await tester.pump();

        expect(
          tester
              .widget<Text>(byTestId(DocumentsTestIds.documentPageIndicator))
              .data,
          'Page 7 of 12',
        );
      },
    );

    testWidgets('writes the pages with the grouping of the language', (
      tester,
    ) async {
      final r = await _render(tester, locale: const Locale('fr'));
      await _opened(tester);

      r.pdf.request.onPageChanged(1234, 5678);
      await tester.pump();

      expect(
        tester
            .widget<Text>(byTestId(DocumentsTestIds.documentPageIndicator))
            .data,
        matches(RegExp(r'^Page 1[   ]234 sur 5[   ]678$')),
      );
    });

    testWidgets(
      'keeps the watermark over the file while the file loads and after',
      (tester) async {
        final r = await _render(tester);
        await _opened(tester);
        final tiles = find.byKey(
          const Key(DocumentsTestIds.documentWatermarkTile),
        );
        final whileLoading = tiles.evaluate().length;

        r.pdf.request.onLoaded(12);
        await tester.pump();

        expect(whileLoading, greaterThan(0));
        expect(tiles.evaluate().length, whileLoading);
      },
    );

    testWidgets(
      'says the file could not be displayed when the view fails, and opens '
      'the document again on retry',
      (tester) async {
        final r = await _render(tester);
        await _opened(tester);

        r.pdf.request.onFailed();
        await tester.pump();

        expect(
          find.descendant(
            of: byTestId(DocumentsTestIds.documentPdfError),
            matching: find.text(en.documentsDocumentRenderFailed),
          ),
          findsOneWidget,
        );
        expect(byTestId(DocumentsTestIds.documentPdf), findsNothing);
        expect(byTestId(DocumentsTestIds.documentWatermark), findsNothing);
        expect(byTestId(DocumentsTestIds.documentPageIndicator), findsNothing);

        await tester.tap(byTestId(CoreTestIds.retryButton));
        await _settle(tester);
        await _opened(tester);

        // The first view was released once, and the document was opened
        // again.
        expect(r.fakes.documents.fetchContentCalls, hasLength(2));
        expect(r.fakes.screenProtection.disableCalls, 1);
        expect(r.fakes.screenProtection.enableCalls, 2);
        expect(r.fakes.screenProtection.enabled, isTrue);
        expect(byTestId(DocumentsTestIds.documentPdfError), findsNothing);
      },
    );
  });

  group('DocumentScreen, a screenshot or a recording', () {
    testWidgets(
      'says calmly that it was seen and recorded, announces it, and has the '
      'use case log it',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final r = await _render(tester);
        await _opened(tester);
        expect(byTestId(DocumentsTestIds.documentCaptureNotice), findsNothing);

        r.fakes.screenProtection.emit(
          const ScreenCaptureEvent(kind: ScreenCaptureKind.screenshotTaken),
        );
        await _settle(tester);

        expect(
          find.descendant(
            of: byTestId(DocumentsTestIds.documentCaptureNotice),
            matching: find.text(en.documentsDocumentCaptureScreenshot),
          ),
          findsOneWidget,
        );
        // It is a live region: the screen reader says it when it appears.
        expect(
          tester
              .getSemantics(
                find.descendant(
                  of: byTestId(DocumentsTestIds.documentCaptureNotice),
                  matching: find.byType(Text),
                ),
              )
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        expect(
          r.fakes.monitoring.loggedEvents(),
          contains(MonitoringEvent.screenCaptureDetected),
        );
        final logged = r.fakes.monitoring.logs.firstWhere(
          (record) => record.event == MonitoringEvent.screenCaptureDetected,
        );
        expect(logged.attributes, {
          LogAttribute.captureKind: ScreenCaptureKind.screenshotTaken.value,
          LogAttribute.documentId: 'report',
          LogAttribute.userId: _reader.id,
        });
        semantics.dispose();
      },
    );

    testWidgets(
      'says it again, and announces it again, for a second screenshot',
      (tester) async {
        final r = await _render(tester);
        await _opened(tester);
        const screenshot = ScreenCaptureEvent(
          kind: ScreenCaptureKind.screenshotTaken,
        );
        Key? keyOfNotice() => tester
            .widget<LiveText>(
              find.descendant(
                of: byTestId(DocumentsTestIds.documentCaptureNotice),
                matching: find.byType(LiveText),
              ),
            )
            .key;

        r.fakes.screenProtection.emit(screenshot);
        await tester.pump();
        final first = keyOfNotice();
        r.fakes.screenProtection.emit(screenshot);
        await tester.pump();

        // A new key makes the live region a new one, which the screen reader
        // says again; there is still one notice on the screen.
        expect(keyOfNotice(), isNot(first));
        expect(
          byTestId(DocumentsTestIds.documentCaptureNotice),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'says a screen recording was seen, and says nothing more when it stops',
      (tester) async {
        final r = await _render(tester);
        await _opened(tester);

        r.fakes.screenProtection.emit(
          const ScreenCaptureEvent(kind: ScreenCaptureKind.recordingStarted),
        );
        await tester.pump();
        Finder notice() => find.descendant(
          of: byTestId(DocumentsTestIds.documentCaptureNotice),
          matching: find.text(en.documentsDocumentCaptureRecording),
        );
        expect(notice(), findsOneWidget);
        r.fakes.screenProtection.emit(
          const ScreenCaptureEvent(kind: ScreenCaptureKind.recordingStopped),
        );
        await tester.pump();

        expect(notice(), findsOneWidget);
      },
    );

    testWidgets(
      'is told for a document that is not confidential too, and can be '
      'dismissed',
      (tester) async {
        final r = await _render(tester, documentId: _pack.id);
        await _opened(tester);

        r.fakes.screenProtection.emit(
          const ScreenCaptureEvent(kind: ScreenCaptureKind.screenshotTaken),
        );
        await tester.pump();
        expect(
          byTestId(DocumentsTestIds.documentCaptureNotice),
          findsOneWidget,
        );
        await tester.tap(byTestId(DocumentsTestIds.documentCaptureDismiss));
        await tester.pump();

        expect(byTestId(DocumentsTestIds.documentCaptureNotice), findsNothing);
      },
    );

    testWidgets(
      'is watched for while the screen is shown, and no longer once it is left',
      (tester) async {
        final r = await _render(tester);
        await _settle(tester);
        expect(r.fakes.screenProtection.listenerCount, 1);

        await _unmount(tester);

        expect(r.fakes.screenProtection.listenerCount, 0);
        r.fakes.screenProtection.emit(
          const ScreenCaptureEvent(kind: ScreenCaptureKind.screenshotTaken),
        );
        await _settle(tester);
        expect(
          r.fakes.monitoring.loggedEvents(),
          isNot(contains(MonitoringEvent.screenCaptureDetected)),
        );
      },
    );

    testWidgets(
      'stops watching when the screen is left before the subscription is made',
      (tester) async {
        final r = await _render(tester);

        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);

        expect(r.fakes.screenProtection.listenerCount, 0);
      },
    );
  });

  group('DocumentScreen, offline', () {
    testWidgets(
      'opens a document already opened from the saved copy, protected, and '
      'says since when',
      (tester) async {
        final fakes = _aWorld();
        await _render(tester, fakes: fakes);
        await _opened(tester);
        await _unmount(tester);
        expect(fakes.screenProtection.enabled, isFalse);
        fakes.network.goOffline();

        final r = await _render(tester, fakes: fakes);
        await _opened(tester);

        expect(
          find.descendant(
            of: byTestId(CoreTestIds.staleBanner),
            matching: find.textContaining(Formatters('en').dateTime(now)),
          ),
          findsOneWidget,
        );
        expect(fakes.screenProtection.enabled, isTrue);
        expect(r.pdf.request.location, _locationOf('report'));
      },
    );

    testWidgets(
      'opens a public document already opened offline protected too: the '
      'copy may be older than its level',
      (tester) async {
        final fakes = _aWorld();
        await _render(tester, documentId: _minutes.id, fakes: fakes);
        await _opened(tester);
        expect(fakes.screenProtection.enabled, isFalse);
        await _unmount(tester);
        fakes.network.goOffline();

        await _render(tester, documentId: _minutes.id, fakes: fakes);
        await _opened(tester);

        expect(fakes.screenProtection.enabled, isTrue);
        expect(
          byTestId(DocumentsTestIds.documentProtectedBadge),
          findsOneWidget,
        );
        expect(
          find
              .byKey(const Key(DocumentsTestIds.documentWatermarkTile))
              .evaluate()
              .length,
          greaterThan(0),
        );
      },
    );

    testWidgets('says a document never opened on this device is not available '
        'offline, and opens it on retry once online', (tester) async {
      final fakes = _aWorld()..network.goOffline();
      await _render(tester, documentId: _pack.id, fakes: fakes);
      await _settle(tester);

      expect(
        find.descendant(
          of: byTestId(DocumentsTestIds.documentError),
          matching: find.text(en.documentsDocumentErrorsNetworkUnavailable),
        ),
        findsOneWidget,
      );
      expect(fakes.screenProtection.enableCalls, 0);
      expect(byTestId(DocumentsTestIds.documentPdf), findsNothing);

      fakes.network.goOnline();
      await tester.tap(byTestId(CoreTestIds.retryButton));
      await _opened(tester);

      expect(byTestId(DocumentsTestIds.documentError), findsNothing);
    });

    testWidgets('says it in French in French', (tester) async {
      final fakes = _aWorld()..network.goOffline();
      await _render(
        tester,
        documentId: _pack.id,
        fakes: fakes,
        locale: const Locale('fr'),
      );
      await _settle(tester);

      final text = _tileTextOf(DocumentsTestIds.documentError);
      expect(text, contains('n’est pas enregistré sur cet appareil'));
      expect(text, contains('hors ligne'));
    });
  });

  group('DocumentScreen, when the document cannot be opened', () {
    final failures =
        <
          (
            String,
            RepositoryError Function(),
            String Function(AppLocalizations),
            bool,
          )
        >[
          (
            'a document that does not exist',
            notFound,
            (l) => l.documentsDocumentNotFound,
            false,
          ),
          (
            'a document the user may not have',
            forbidden,
            (l) => l.documentsDocumentErrorsForbidden,
            false,
          ),
          (
            'a fault of the server',
            () => unexpected('status 500'),
            (l) => l.coreErrorsUnexpected,
            true,
          ),
        ];
    for (final (name, failure, message, retry) in failures) {
      testWidgets('says $name, and offers a retry only when it can help', (
        tester,
      ) async {
        final fakes = _aWorld()..documents.failure = failure();
        await _render(tester, documentId: _pack.id, fakes: fakes);
        await _settle(tester);

        expect(
          find.descendant(
            of: byTestId(DocumentsTestIds.documentError),
            matching: find.text(message(en)),
          ),
          findsOneWidget,
        );
        expect(
          byTestId(CoreTestIds.retryButton),
          retry ? findsOneWidget : findsNothing,
        );
        expect(fakes.screenProtection.enableCalls, 0);
      });
    }

    testWidgets(
      'does not show a confidential document the screen of which cannot be '
      'protected, and says why',
      (tester) async {
        final fakes = _aWorld()
          ..screenProtection.enableFailure = screenProtectionUnsupported();
        await _render(tester, fakes: fakes);
        await _settle(tester);

        expect(
          find.descendant(
            of: byTestId(DocumentsTestIds.documentError),
            matching: find.text(
              en.documentsDocumentErrorsScreenProtectionUnsupported,
            ),
          ),
          findsOneWidget,
        );
        expect(byTestId(CoreTestIds.retryButton), findsNothing);
        expect(byTestId(DocumentsTestIds.documentPdf), findsNothing);
        expect(fakes.screenProtection.enabled, isFalse);
      },
    );

    testWidgets(
      'offers a retry when the protection failed, and shows the document '
      'once it works',
      (tester) async {
        final fakes = _aWorld()
          ..screenProtection.enableFailure = screenProtectionFailed();
        await _render(tester, fakes: fakes);
        await _settle(tester);
        expect(
          find.descendant(
            of: byTestId(DocumentsTestIds.documentError),
            matching: find.text(
              en.documentsDocumentErrorsScreenProtectionFailed,
            ),
          ),
          findsOneWidget,
        );

        fakes.screenProtection.enableFailure = null;
        await tester.tap(byTestId(CoreTestIds.retryButton));
        await _opened(tester);

        expect(fakes.screenProtection.enabled, isTrue);
      },
    );

    testWidgets(
      'says a document id that is no id is not found, without asking for '
      'anything',
      (tester) async {
        final r = await _render(tester, documentId: ' ');

        expect(
          find.descendant(
            of: byTestId(DocumentsTestIds.documentNotFound),
            matching: find.text(en.documentsDocumentNotFound),
          ),
          findsOneWidget,
        );
        expect(byTestId(DocumentsTestIds.documentScreen), findsNothing);
        expect(r.fakes.documents.getCalls, isEmpty);
      },
    );

    testWidgets('says there is no document when the route has none', (
      tester,
    ) async {
      await _render(tester, documentId: '');

      expect(byTestId(DocumentsTestIds.documentNotFound), findsOneWidget);
    });

    testWidgets(
      'ends the session for the whole app when the server refuses it',
      (tester) async {
        final fakes = _aWorld()..documents.failure = unauthorized();
        final r = await _render(tester, documentId: _pack.id, fakes: fakes);
        await _settle(tester);

        final access = r.providers.read(accessControllerProvider);
        expect(access.access, Access.signedOut);
        expect(access.sessionEndedBy, 'unauthorized');
      },
    );

    testWidgets(
      'says the network is out of reach for a request that fails on a '
      'document never opened',
      (tester) async {
        final fakes = _aWorld()..documents.failure = networkUnavailable();
        await _render(tester, documentId: _pack.id, fakes: fakes);
        await _settle(tester);

        expect(byTestId(DocumentsTestIds.documentError), findsOneWidget);
      },
    );
  });

  group('DocumentScreen, opened and closed', () {
    testWidgets(
      'keeps the screen protected until the last view of a document is closed',
      (tester) async {
        final fakes = _aWorld();
        final pdf = FakePdfViews();
        final providers = TestApp(fakes: fakes)
            .providers(extra: [pdf.override]);
        await tester.pumpWidget(
          testHost(
            providers,
            Column(
              children: [
                Expanded(child: DocumentScreen(documentId: _report.id)),
                Expanded(
                  child: _Toggle(child: DocumentScreen(documentId: _report.id)),
                ),
              ],
            ),
          ),
        );
        await _settle(tester);
        expect(fakes.documents.fetchContentCalls, hasLength(2));
        expect(fakes.screenProtection.enableCalls, 2);

        // Leave the second view.
        tester.state<_ToggleState>(find.byType(_Toggle)).hide();
        await tester.pump();
        await _settle(tester);
        expect(fakes.screenProtection.enabled, isTrue);
        expect(fakes.screenProtection.disableCalls, 0);

        await _unmount(tester);
        expect(fakes.screenProtection.enabled, isFalse);
        expect(fakes.screenProtection.disableCalls, 1);
      },
    );

    testWidgets(
      'opens and closes each time the screen is shown again, once each',
      (tester) async {
        final fakes = _aWorld();
        for (var round = 1; round <= 3; round += 1) {
          await _render(tester, fakes: fakes);
          await _settle(tester);
          expect(fakes.screenProtection.enabled, isTrue);
          await _unmount(tester);
          expect(fakes.screenProtection.enabled, isFalse);
          expect(fakes.screenProtection.enableCalls, round);
          expect(fakes.screenProtection.disableCalls, round);
        }
      },
    );

    testWidgets('releases a document that opens after the screen was left', (
      tester,
    ) async {
      final fakes = _aWorld();
      final slow = Completer<void>();
      fakes.documents.onRequest = () => slow.future;
      await _render(tester, fakes: fakes);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(fakes.screenProtection.disableCalls, 0);
      slow.complete();
      await _settle(tester);

      expect(fakes.screenProtection.enabled, isFalse);
      expect(fakes.screenProtection.enableCalls, 1);
      expect(fakes.screenProtection.disableCalls, 1);
    });

    testWidgets(
      'closes the document, and shows nothing of it, when the app stops '
      'being open',
      (tester) async {
        final r = await _render(tester);
        await _opened(tester);

        r.providers.read(accessControllerProvider.notifier).signedOut();
        await _settle(tester);

        expect(r.fakes.screenProtection.enabled, isFalse);
        expect(r.fakes.screenProtection.disableCalls, 1);
        expect(byTestId(DocumentsTestIds.documentPdf), findsNothing);
        expect(byTestId(DocumentsTestIds.documentWatermark), findsNothing);
        expect(find.text('Remuneration report'), findsNothing);
      },
    );
  });

  group('DocumentScreen, in a navigator', () {
    Future<void> pushOver(WidgetTester tester) async {
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
          );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
    }

    testWidgets(
      'releases the document when another screen is put over it, and opens '
      'it again when the user comes back',
      (tester) async {
        final r = await _render(tester);
        await _opened(tester);
        expect(r.fakes.screenProtection.enabled, isTrue);

        await pushOver(tester);

        expect(r.fakes.screenProtection.enabled, isFalse);
        expect(r.fakes.screenProtection.disableCalls, 1);
        expect(byTestId(DocumentsTestIds.documentPdf), findsNothing);
        expect(r.fakes.screenProtection.listenerCount, 0);

        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await _opened(tester);

        expect(r.fakes.screenProtection.enabled, isTrue);
        expect(r.fakes.documents.fetchContentCalls, hasLength(2));
        expect(r.fakes.screenProtection.listenerCount, 1);
      },
    );

    testWidgets(
      'does not open a document for a screen that is mounted under another',
      (tester) async {
        final fakes = _aWorld();
        final providers = TestApp(fakes: fakes).providers();
        await tester.pumpWidget(
          testHost(
            providers,
            _MountUnder(DocumentScreen(documentId: _report.id)),
          ),
        );
        await _settle(tester);
        await tester.pump(const Duration(seconds: 1));
        await _settle(tester);

        expect(fakes.documents.fetchContentCalls, isEmpty);
        expect(fakes.screenProtection.enableCalls, 0);
      },
    );
  });

  group('DocumentScreen, in French', () {
    testWidgets(
      'says the screen is protected, the page, the notice and the watermark '
      'time in French',
      (tester) async {
        const fr = Locale('fr');
        final r = await _render(tester, locale: fr);
        await _opened(tester);
        r.pdf.request.onLoaded(12);
        r.fakes.screenProtection.emit(
          const ScreenCaptureEvent(kind: ScreenCaptureKind.screenshotTaken),
        );
        await _settle(tester);

        expect(
          find.descendant(
            of: byTestId(DocumentsTestIds.documentProtectedBadge),
            matching: find.text('Écran protégé'),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(byTestId(DocumentsTestIds.documentPageIndicator))
              .data,
          'Page 1 sur 12',
        );
        expect(
          find.descendant(
            of: byTestId(DocumentsTestIds.documentCaptureNotice),
            matching: find.text(
              'Une capture d’écran a été détectée. Elle a été consignée.',
            ),
          ),
          findsOneWidget,
        );
        expect(
          _tileText(),
          [
            _reader.fullName,
            _reader.email,
            Formatters('fr').dateTime(now),
          ].join('\n'),
        );
        expect(find.text('Confidentiel'), findsOneWidget);
      },
    );

    testWidgets('loads in French', (tester) async {
      final semantics = tester.ensureSemantics();
      await _render(tester, locale: const Locale('fr'));

      expect(find.bySemanticsLabel('Ouverture du document'), findsOneWidget);
      await _opened(tester);
      semantics.dispose();
    });

    testWidgets('says in French that the pdf is loading', (tester) async {
      final semantics = tester.ensureSemantics();
      final r = await _render(tester, locale: const Locale('fr'));
      await _opened(tester);

      expect(find.bySemanticsLabel('Affichage du document'), findsOneWidget);
      expect(r.pdf.mounted, 1);
      semantics.dispose();
    });
  });

  group('DocumentScreen, while the app is not active', () {
    testWidgets(
      'unmounts the PDF view as soon as the privacy cover goes up, and '
      'mounts it again, from the first page, when it is lifted',
      (tester) async {
        final r = await _render(tester);
        await _opened(tester);
        r.pdf.request.onLoaded(12);
        r.pdf.request.onPageChanged(7, 12);
        await tester.pump();
        Text indicator() => tester.widget<Text>(
          byTestId(DocumentsTestIds.documentPageIndicator),
        );
        expect(indicator().data, 'Page 7 of 12');
        expect(r.pdf.mounted, 1);

        r.providers.read(privacyCoverUpProvider.notifier).set(true);
        await tester.pump();

        expect(byTestId(DocumentsTestIds.documentPdf), findsNothing);
        expect(r.pdf.latest, isNull);
        expect(byTestId(DocumentsTestIds.documentPageIndicator), findsNothing);
        expect(byTestId(DocumentsTestIds.documentWatermark), findsNothing);
        // The document is still open and protected: only the view is gone.
        expect(find.text('Remuneration report'), findsOneWidget);

        r.providers.read(privacyCoverUpProvider.notifier).set(false);
        await tester.pump();

        expect(byTestId(DocumentsTestIds.documentPdf), findsOneWidget);
        expect(r.pdf.mounted, 2);
        expect(r.pdf.request.location, _locationOf('report'));
        expect(byTestId(DocumentsTestIds.documentPdfLoading), findsOneWidget);
        expect(byTestId(DocumentsTestIds.documentPageIndicator), findsNothing);
        r.pdf.request.onLoaded(12);
        await tester.pump();
        expect(indicator().data, en.documentsDocumentPageIndicator('1', '12'));
      },
    );

    testWidgets(
      'neither opens nor closes the document for it: the screen stays '
      'protected while it is covered',
      (tester) async {
        final r = await _render(tester);
        await _opened(tester);

        r.providers.read(privacyCoverUpProvider.notifier).set(true);
        await tester.pump();
        r.providers.read(privacyCoverUpProvider.notifier).set(false);
        await tester.pump();

        expect(r.fakes.documents.fetchContentCalls, hasLength(1));
        expect(r.fakes.screenProtection.enabled, isTrue);
        expect(r.fakes.screenProtection.disableCalls, 0);
      },
    );

    testWidgets(
      'keeps the PDF view out while the cover stays up, whatever else the '
      'screen does',
      (tester) async {
        final r = await _render(tester);
        await _opened(tester);
        r.providers.read(privacyCoverUpProvider.notifier).set(true);
        await tester.pump();

        r.fakes.screenProtection.emit(
          const ScreenCaptureEvent(kind: ScreenCaptureKind.screenshotTaken),
        );
        await tester.pump();

        expect(
          byTestId(DocumentsTestIds.documentCaptureNotice),
          findsOneWidget,
        );
        expect(byTestId(DocumentsTestIds.documentPdf), findsNothing);
        expect(r.pdf.mounted, 1);
      },
    );

    testWidgets(
      'shows no PDF view for a document that opens while the cover is up, '
      'until it is lifted',
      (tester) async {
        final r = await _render(tester);
        r.providers.read(privacyCoverUpProvider.notifier).set(true);
        await _settle(tester);
        expect(byTestId(DocumentsTestIds.documentTitle), findsOneWidget);

        expect(r.pdf.mounted, 0);
        expect(byTestId(DocumentsTestIds.documentPdf), findsNothing);

        r.providers.read(privacyCoverUpProvider.notifier).set(false);
        await tester.pump();

        expect(byTestId(DocumentsTestIds.documentPdf), findsOneWidget);
      },
    );
  });
}

/// Shows its child until `hide` is called.
class _Toggle extends StatefulWidget {
  const new({required this.child});

  final Widget child;

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _shown = true;

  void hide() => setState(() => _shown = false);

  @override
  Widget build(BuildContext context) =>
      _shown ? widget.child : const SizedBox.shrink();
}

/// Pushes [screen] and a second screen over it in the same frame, so the first
/// is built when it is already under the other.
class _MountUnder extends StatefulWidget {
  const new(this.screen);

  final Widget screen;

  @override
  State<_MountUnder> createState() => _MountUnderState();
}

class _MountUnderState extends State<_MountUnder> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context)
        ..push(MaterialPageRoute<void>(builder: (_) => widget.screen))
        ..push(
          MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
        );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
