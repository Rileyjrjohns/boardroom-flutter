import 'package:boardroom/features/documents/presentation/components/pdf_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the screen asks of a PDF view and how the view answers.
@immutable
final class PdfViewRequest {
  /// Creates the request to draw the file at [location].
  const new({
    required this.location,
    required this.onLoaded,
    required this.onPageChanged,
    required this.onFailed,
  });

  /// Where the file is: the location `OpenDocument` gave, a file of the device.
  final String location;

  /// The file was read: how many pages it has.
  final void Function(int pageCount) onLoaded;

  /// The page on display changed (the first one, once the file is read,
  /// included).
  final void Function(int page, int pageCount) onPageChanged;

  /// The file could not be read or drawn.
  final VoidCallback onFailed;
}

/// Builds the widget that draws a PDF.
typedef PdfViewBuilder = Widget Function(PdfViewRequest request);

/// The PDF view the screen mounts: [PdfView], the one widget that uses the PDF
/// package. A widget test overrides it with a fake that it drives by hand,
/// since the real one needs the PDF engine of a device (the same way the React
/// Native tests stub `react-native-pdf`).
final pdfViewBuilderProvider = Provider<PdfViewBuilder>(
  (ref) =>
      (request) => PdfView(
        key: ValueKey(request.location),
        location: request.location,
        onLoaded: request.onLoaded,
        onPageChanged: request.onPageChanged,
        onFailed: request.onFailed,
      ),
);
