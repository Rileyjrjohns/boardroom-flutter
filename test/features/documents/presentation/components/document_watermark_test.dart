import 'dart:math' as math;

import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart' as tokens;
import 'package:boardroom/features/documents/domain/value_objects/watermark.dart';
import 'package:boardroom/features/documents/presentation/components/document_watermark.dart';
import 'package:boardroom/features/documents/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/presentation/test_app.dart';

final Watermark _reader = createWatermark(aUser(), now);

Finder _overlay() => byTestId(DocumentsTestIds.documentWatermark);
Finder _tiles() => byTestId(DocumentsTestIds.documentWatermarkTile);

/// Puts the watermark over an area of [width] x [height].
Future<void> _pumpWatermark(
  WidgetTester tester, {
  double width = 400,
  double height = 800,
  Locale locale = const Locale('en'),
}) async {
  // A window big enough for the biggest area of the tests.
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(2000, 2000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(children: [DocumentWatermark(watermark: _reader)]),
        ),
      ),
    ),
  );
}

/// The transforms of the grid, in the order of the tree: the turn of the
/// square first, then one translation for each row.
List<Transform> _transforms(WidgetTester tester) => tester
    .widgetList<Transform>(
      find.descendant(of: _overlay(), matching: find.byType(Transform)),
    )
    .toList();

void main() {
  group('watermarkLines', () {
    test('says the full name, the email and the moment, written by '
        'the function it is given', () {
      final lines = watermarkLines(_reader, (instant) => 'at $instant');

      expect(lines, [_reader.fullName, _reader.email, 'at $now']);
    });
  });

  group('DocumentWatermark', () {
    group('the text', () {
      testWidgets(
        'is the name, the email and the moment of the opening, one under '
        'the other, on every tile',
        (tester) async {
          await _pumpWatermark(tester);

          final expected = [
            _reader.fullName,
            _reader.email,
            Formatters('en').dateTime(now),
          ].join('\n');
          for (final tile in _tiles().evaluate()) {
            expect((tile.widget as Text).data, expected);
          }
        },
      );

      testWidgets('writes the moment for the locale of the app', (
        tester,
      ) async {
        await _pumpWatermark(tester);
        final inEnglish = Formatters('en').dateTime(now);
        expect(
          (_tiles().evaluate().first.widget as Text).data,
          contains(inEnglish),
        );

        await _pumpWatermark(tester, locale: const Locale('fr'));

        final inFrench = Formatters('fr').dateTime(now);
        expect(inFrench, isNot(inEnglish));
        expect(
          (_tiles().evaluate().first.widget as Text).data,
          contains(inFrench),
        );
      });

      testWidgets('is the watermark of the domain and nothing more', (
        tester,
      ) async {
        await _pumpWatermark(tester);

        final everything = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join();
        expect(everything, isNot(matches(RegExp('user-1|password|token'))));
      });
    });

    group('the tiling', () {
      testWidgets(
        'covers the window when the area has no size of its own, so the '
        'page is never bare',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: UnconstrainedBox(
                child: Stack(children: [DocumentWatermark(watermark: _reader)]),
              ),
            ),
          );

          expect(_tiles().evaluate().length, greaterThan(20));
        },
      );

      testWidgets(
        'covers the diagonal of the area: rows and columns of tiles, one '
        'more column for the shifted rows',
        (tester) async {
          await _pumpWatermark(tester);

          final (:rows, :columns, diagonal: _) = watermarkGrid(400, 800);
          expect(_tiles().evaluate().length, rows * columns);
        },
      );

      testWidgets(
        'adds tiles when the area grows and removes them when it shrinks',
        (tester) async {
          await _pumpWatermark(tester);
          final small = _tiles().evaluate().length;

          await _pumpWatermark(tester, width: 800, height: 1600);
          final large = _tiles().evaluate().length;
          await _pumpWatermark(tester);

          expect(large, greaterThan(small));
          expect(_tiles().evaluate().length, small);
        },
      );

      testWidgets(
        'turns the grid by the angle of the tokens, on a square as big as '
        'the diagonal, centred on the area',
        (tester) async {
          await _pumpWatermark(tester);

          final (:diagonal, rows: _, columns: _) = watermarkGrid(400, 800);
          final turn = _transforms(tester).first.transform;
          const angle = tokens.Watermark.angleDegrees * math.pi / 180;
          expect(turn.entry(0, 0), closeTo(math.cos(angle), 1e-9));
          expect(turn.entry(1, 0), closeTo(math.sin(angle), 1e-9));
          final square = tester.widget<Positioned>(
            find.descendant(of: _overlay(), matching: find.byType(Positioned)),
          );
          expect(square.width, diagonal);
          expect(square.height, diagonal);
          expect(square.left, (400 - diagonal) / 2);
          expect(square.top, (800 - diagonal) / 2);
        },
      );

      testWidgets('shifts every other row by half a tile', (tester) async {
        await _pumpWatermark(tester);

        final shifts = _transforms(tester)
            .skip(1)
            .take(4)
            .map((row) => row.transform.getTranslation().x)
            .toList();

        expect(shifts, [
          0,
          -tokens.Watermark.tileWidth / 2,
          0,
          -tokens.Watermark.tileWidth / 2,
        ]);
      });

      testWidgets(
        'sizes each tile and draws it faint, in the colour of the tokens',
        (tester) async {
          await _pumpWatermark(tester);

          final tile = _tiles().evaluate().first.widget as Text;
          expect(tile.style?.fontSize, tokens.Watermark.fontSize);
          expect(
            tile.style?.color,
            tokens.AppColors.watermarkText.withValues(
              alpha: tokens.Watermark.opacity,
            ),
          );
          expect(tile.maxLines, 3);
          expect(
            tester.getSize(
              find
                  .ancestor(of: _tiles().first, matching: find.byType(SizedBox))
                  .first,
            ),
            const Size(tokens.Watermark.tileWidth, tokens.Watermark.tileHeight),
          );
          expect(tokens.Watermark.opacity, greaterThan(0));
          expect(tokens.Watermark.opacity, lessThan(0.5));
        },
      );

      test(
        'slants the text, so that it cannot be cropped out with a straight cut',
        () {
          expect(tokens.Watermark.angleDegrees % 90, isNot(0));
        },
      );
    });

    group('being in the way', () {
      testWidgets(
        'takes no touch: the page under it scrolls, zooms and follows links '
        'as if it were not there',
        (tester) async {
          await _pumpWatermark(tester);

          final ignore = tester.widget<IgnorePointer>(
            find.descendant(
              of: _overlay(),
              matching: find.byType(IgnorePointer),
            ),
          );
          expect(ignore.ignoring, isTrue);
        },
      );

      testWidgets('fills the area it is put over, and is clipped to it', (
        tester,
      ) async {
        await _pumpWatermark(tester);

        expect(tester.getSize(_overlay()), const Size(400, 800));
        expect(
          find.descendant(of: _overlay(), matching: find.byType(ClipRect)),
          findsOneWidget,
        );
      });

      testWidgets(
        'is hidden from the screen reader, so a name repeated forty times '
        'is not read out',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await _pumpWatermark(tester);

          final excluded = tester.widget<ExcludeSemantics>(
            find.descendant(
              of: _overlay(),
              matching: find.byType(ExcludeSemantics),
            ),
          );
          expect(excluded.excluding, isTrue);
          expect(find.bySemanticsLabel(RegExp(_reader.fullName)), findsNothing);
          semantics.dispose();
        },
      );
    });
  });
}
