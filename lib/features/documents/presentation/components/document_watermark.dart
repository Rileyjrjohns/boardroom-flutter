import 'dart:math' as math;

import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart' as tokens;
import 'package:boardroom/features/documents/domain/value_objects/watermark.dart';
import 'package:boardroom/features/documents/presentation/test_ids.dart';
import 'package:flutter/widgets.dart';

/// The text of one tile, line by line: the full name and the email of the
/// reader, and the moment the document was opened, written for the locale of
/// the app. The domain fixes what the watermark says ([Watermark]); how the
/// instant is written is the one thing decided here.
List<String> watermarkLines(
  Watermark watermark,
  String Function(Instant instant) formatInstant,
) => [watermark.fullName, watermark.email, formatInstant(watermark.viewedAt)];

const String _lineBreak = '\n';
const int _half = 2;

/// How many rows and columns of tiles cover an area of [width] x [height], on a
/// square as wide as the diagonal: one more column than fits, for the rows
/// that are shifted by half a tile.
({int diagonal, int rows, int columns}) watermarkGrid(
  double width,
  double height,
) {
  final diagonal = math.sqrt(width * width + height * height).ceil();
  return (
    diagonal: diagonal,
    rows: (diagonal / tokens.Watermark.tileHeight).ceil(),
    columns: (diagonal / tokens.Watermark.tileWidth).ceil() + 1,
  );
}

/// Tiles the watermark across the whole area it is put over, slanted, faint,
/// and above the page.
///
/// - **Diagonal across the whole area.** The tiles are laid out in rows on a
///   square as big as the diagonal of the area, centred on it and turned by the
///   angle of the tokens, so that after the turn they still cover every corner.
///   Alternate rows are shifted by half a tile, which keeps a whole line of
///   text from standing in the same column down the page.
/// - **Faint.** Every tile has the opacity of the tokens: the page stays
///   readable, and the name stays readable on a screenshot.
/// - **Never in the way.** It takes no touch, so the page under it scrolls,
///   zooms and follows links as if it were not there.
/// - **Not read out.** It is hidden from screen readers, since a name and an
///   email repeated forty times says nothing to someone who cannot see the
///   page.
///
/// The size of the area is the one it is laid out in, so there is never a
/// moment when the page is shown bare.
class DocumentWatermark extends StatelessWidget {
  /// Creates the overlay for [watermark], the reader of the document.
  const new({required this.watermark, super.key});

  /// What the domain says the page must show: who is reading, and since when.
  final Watermark watermark;

  @override
  Widget build(BuildContext context) {
    final text = watermarkLines(
      watermark,
      Formatters.of(context).dateTime,
    ).join(_lineBreak);
    final window = MediaQuery.sizeOf(context);

    return KeyedSubtree(
      key: const Key(DocumentsTestIds.documentWatermark),
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : window.width;
              final height = constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : window.height;
              return SizedBox(
                width: width,
                height: height,
                child: ClipRect(child: _Tiles(width, height, text)),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Tiles extends StatelessWidget {
  const new(this.width, this.height, this.text);

  final double width;
  final double height;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (:diagonal, :rows, :columns) = watermarkGrid(width, height);
    final style = TextStyle(
      fontSize: tokens.Watermark.fontSize,
      color: tokens.AppColors.watermarkText.withValues(
        alpha: tokens.Watermark.opacity,
      ),
    );

    return Stack(
      children: [
        Positioned(
          left: (width - diagonal) / _half,
          top: (height - diagonal) / _half,
          width: diagonal.toDouble(),
          height: diagonal.toDouble(),
          child: Transform.rotate(
            angle: tokens.Watermark.angleDegrees * math.pi / 180,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < rows; row += 1)
                    Transform.translate(
                      offset: Offset(
                        row.isOdd ? -tokens.Watermark.tileWidth / _half : 0,
                        0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var column = 0; column < columns; column += 1)
                            _Tile(text: text, style: style),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const new({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: tokens.Watermark.tileWidth,
    height: tokens.Watermark.tileHeight,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: tokens.AppSpacing.sm),
        child: Text(
          text,
          key: const Key(DocumentsTestIds.documentWatermarkTile),
          maxLines: 3,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.center,
          style: style,
        ),
      ),
    ),
  );
}
