import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/presentation/components/document_row.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/presentation/test_app.dart';

/// Mounts the row of a document and returns its finder.
Future<Finder> _renderDocument(
  WidgetTester tester, {
  String title = 'Board pack',
  ConfidentialityLevel confidentiality = ConfidentialityLevel.internal,
  num pageCount = 3,
  Locale locale = const Locale('en'),
  VoidCallback? onOpen,
}) async {
  final document = aDocument(
    id: aDocumentId('doc'),
    title: title,
    confidentiality: confidentiality,
    pageCount: pageCount,
  );
  await pumpScreen(
    tester,
    DocumentRow(document: document, onOpen: onOpen ?? () {}),
    locale: locale,
  );
  return byTestId(documentTestId(document.id));
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  final en = l10nOf();
  final fr = l10nOf(const Locale('fr'));

  group('DocumentRow', () {
    group('as a button', () {
      testWidgets('opens its document when it is pressed', (tester) async {
        var opened = 0;
        final row = await _renderDocument(tester, onOpen: () => opened += 1);

        await tester.tap(row);

        expect(opened, 1);
      });

      testWidgets(
        'is a button for the screen reader, named by its title, its level and '
        'its pages, with a hint',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final row = await _renderDocument(tester, pageCount: 4);

          expect(
            tester.getSemantics(row),
            isSemantics(
              isButton: true,
              label:
                  'Board pack, ${en.meetingsConfidentialityInternal}, 4 pages',
              hint: en.meetingsMeetingOpenDocumentHint,
            ),
          );
          semantics.dispose();
        },
      );

      testWidgets(
        'is named in French in French, with the number of pages written the '
        'French way',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final row = await _renderDocument(
            tester,
            title: 'Dossier',
            pageCount: 1234,
            locale: const Locale('fr'),
          );

          final data = tester.getSemantics(row).getSemanticsData();
          expect(
            data.label,
            matches(
              RegExp(
                '^Dossier, ${fr.meetingsConfidentialityInternal}, '
                r'1[   ]234 pages$',
              ),
            ),
          );
          expect(data.hint, fr.meetingsMeetingOpenDocumentHint);
          semantics.dispose();
        },
      );

      testWidgets('is at least as tall as a touch target', (tester) async {
        final row = await _renderDocument(tester);

        expect(
          tester.getSize(row).height,
          greaterThanOrEqualTo(AppSizes.touchTargetMin),
        );
      });
    });

    testWidgets(
      'shows the title, the confidentiality and the number of pages',
      (tester) async {
        final row = await _renderDocument(tester, pageCount: 4);

        for (final text in [
          'Board pack',
          en.meetingsConfidentialityInternal,
          '4 pages',
        ]) {
          expect(
            find.descendant(of: row, matching: find.text(text)),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets('marks a confidential document in red', (tester) async {
      await _renderDocument(
        tester,
        confidentiality: ConfidentialityLevel.confidential,
      );

      expect(
        _colorOf(tester, en.meetingsConfidentialityConfidential),
        AppColors.confidentialBadgeText,
      );
    });

    for (final level in [
      ConfidentialityLevel.public,
      ConfidentialityLevel.internal,
    ]) {
      testWidgets('marks a ${level.value} document in neutral', (tester) async {
        await _renderDocument(tester, confidentiality: level);

        final label = switch (level) {
          ConfidentialityLevel.public => en.meetingsConfidentialityPublic,
          _ => en.meetingsConfidentialityInternal,
        };
        expect(_colorOf(tester, label), AppColors.neutralBadgeText);
      });
    }

    group('the number of pages', () {
      testWidgets('is written with the grouping of the language', (
        tester,
      ) async {
        final row = await _renderDocument(tester, pageCount: 1234);

        expect(
          find.descendant(of: row, matching: find.text('1,234 pages')),
          findsOneWidget,
        );
      });

      testWidgets('is written the French way in French', (tester) async {
        final row = await _renderDocument(
          tester,
          pageCount: 1234,
          locale: const Locale('fr'),
        );

        expect(
          find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  RegExp(r'^1[   ]234 pages$').hasMatch(widget.data!),
            ),
          ),
          findsOneWidget,
        );
      });

      testWidgets('says one page for one', (tester) async {
        final row = await _renderDocument(tester, pageCount: 1);

        expect(
          find.descendant(of: row, matching: find.text('1 page')),
          findsOneWidget,
        );
      });
    });
  });
}
