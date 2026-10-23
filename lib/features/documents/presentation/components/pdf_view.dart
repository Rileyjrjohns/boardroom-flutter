import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

/// The parameters the viewer is given, apart so that a test can read them.
///
/// A confidential document needs what leads out of it off: the links go
/// nowhere (no link handler is set, so a tap on one does nothing), the
/// annotations and forms are not drawn, and the text cannot be selected (so it
/// cannot be copied out). The package has no progress of its own to turn off:
/// it only draws what the builders below give it, and the screen draws its own
/// loading veil.
PdfViewerParams pdfViewerParams({
  required void Function(int pageCount) onLoaded,
  required void Function(int page, int pageCount) onPageChanged,
  required VoidCallback onFailed,
  required PdfViewerController controller,
}) => PdfViewerParams(
  backgroundColor: AppColors.documentBackdrop,
  annotationRenderingMode: PdfAnnotationRenderingMode.none,
  textSelectionParams: const PdfTextSelectionParams(enabled: false),
  onViewerReady: (document, _) => onLoaded(document.pages.length),
  onPageChanged: (page) {
    if (page != null) {
      onPageChanged(page, controller.pageCount);
    }
  },
  onDocumentLoadFinished: (_, loadSucceeded) {
    if (!loadSucceeded) {
      onFailed();
    }
  },
  loadingBannerBuilder: (context, downloaded, total) => const SizedBox.shrink(),
  errorBannerBuilder: (context, error, stackTrace, documentRef) =>
      const SizedBox.shrink(),
);

/// Draws a PDF from a file of the device, with the viewer of `pdfrx`. **The one
/// file that imports the package**, and as small as it can be: it renames what
/// the viewer reports and sets what a confidential document needs off. It
/// reports the failure and nothing of why: the reason holds the path of the
/// file.
///
/// The viewer draws the pages with Flutter, so the watermark the screen lays
/// over it and the secure container around it work as for any widget.
class PdfView extends StatefulWidget {
  /// Creates a view of the file at [location].
  const new({
    required this.location,
    required this.onLoaded,
    required this.onPageChanged,
    required this.onFailed,
    super.key,
  });

  /// Where the file is: a `file:` URI, or a path.
  final String location;

  /// The file was read: how many pages it has.
  final void Function(int pageCount) onLoaded;

  /// The page on display changed.
  final void Function(int page, int pageCount) onPageChanged;

  /// The file could not be read or drawn.
  final VoidCallback onFailed;

  @override
  State<PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<PdfView> {
  final PdfViewerController _controller = PdfViewerController();

  /// The viewer wants a path, and the use case gives a URI.
  String get _path {
    final uri = Uri.tryParse(widget.location);
    return uri != null && uri.isScheme('file')
        ? uri.toFilePath()
        : widget.location;
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.documentBackdrop,
    child: PdfViewer.file(
      _path,
      controller: _controller,
      params: pdfViewerParams(
        controller: _controller,
        onLoaded: widget.onLoaded,
        onPageChanged: widget.onPageChanged,
        onFailed: widget.onFailed,
      ),
    ),
  );
}
