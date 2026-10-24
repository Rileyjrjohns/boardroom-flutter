import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

// Test support, not production code: how the golden images are compared.
//
// The images are drawn by the software renderer of Flutter, which smooths the
// edges of rounded corners and of lines in a slightly different way on macOS
// and on Linux: about 0.6 percent of the pixels of an image differ by a shade
// there, and nothing else. An exact comparison would fail on one of the two
// systems. A real change of a screen (a text of another length, a colour, a
// moved element) changes whole areas, not lines of one or two pixels.
//
// So an image is accepted when it is the same size and the pixels that differ
// form no area: a pixel counts as part of an area when at least six of its
// eight neighbours differ too. Any other difference is reported by the usual
// comparator, with the images of the expected, the actual and the difference.

/// How many neighbours of a pixel (of eight) must differ too for the pixel to
/// be part of an area that changed, not of a smoothed edge.
const int _neighboursOfAnArea = 6;

/// How many pixels of areas are tolerated before the image is refused.
const int _tolerableAreaPixels = 16;

/// A comparator that ignores the smoothing of the edges.
class EdgeTolerantComparator extends LocalFileComparator {
  /// Creates the comparator for the goldens next to [testFile].
  new(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final expected = Uint8List.fromList(await getGoldenBytes(golden));
    if (await _sameUpToEdges(imageBytes, expected)) {
      return true;
    }
    // Differs for real, or by an exact byte: the usual comparison fails with a
    // report of the difference.
    return await super.compare(imageBytes, golden);
  }
}

Future<bool> _sameUpToEdges(Uint8List actual, Uint8List expected) async {
  final a = await _decode(actual);
  final b = await _decode(expected);
  if (a.width != b.width || a.height != b.height) {
    return false;
  }
  final width = a.width;
  final height = a.height;
  final differs = List<bool>.filled(width * height, false);
  for (var i = 0; i < width * height; i += 1) {
    for (var channel = 0; channel < 4; channel += 1) {
      if (a.pixels.getUint8(i * 4 + channel) !=
          b.pixels.getUint8(i * 4 + channel)) {
        differs[i] = true;
        break;
      }
    }
  }
  var inAreas = 0;
  for (var y = 1; y < height - 1; y += 1) {
    for (var x = 1; x < width - 1; x += 1) {
      if (!differs[y * width + x]) {
        continue;
      }
      var neighbours = 0;
      for (var dy = -1; dy <= 1; dy += 1) {
        for (var dx = -1; dx <= 1; dx += 1) {
          if ((dx != 0 || dy != 0) && differs[(y + dy) * width + x + dx]) {
            neighbours += 1;
          }
        }
      }
      if (neighbours >= _neighboursOfAnArea) {
        inAreas += 1;
        if (inAreas > _tolerableAreaPixels) {
          return false;
        }
      }
    }
  }
  return true;
}

Future<({int width, int height, ByteData pixels})> _decode(
  Uint8List bytes,
) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final pixels = await image.toByteData();
  final decoded = (width: image.width, height: image.height, pixels: pixels!);
  image.dispose();
  codec.dispose();
  return decoded;
}
