import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/documents/presentation/components/pdf_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

// The component that draws a PDF is the one file that imports `pdfrx`. The
// viewer itself needs the PDF engine of a device, so what is checked is the
// conversation with it: what it is told to leave off, and the way the
// parameters report back (the screen's tests use a fake of the whole view).

PdfViewerParams _params({
  void Function(int)? onLoaded,
  void Function(int, int)? onPageChanged,
  void Function()? onFailed,
  PdfViewerController? controller,
}) => pdfViewerParams(
  controller: controller ?? PdfViewerController(),
  onLoaded: onLoaded ?? (_) {},
  onPageChanged: onPageChanged ?? (_, _) {},
  onFailed: onFailed ?? () {},
);

class _Page extends Fake implements PdfPage;

class _Document extends Fake implements PdfDocument {
  new(this.count);

  final int count;

  @override
  List<PdfPage> get pages => List.generate(count, (_) => _Page());
}

class _Ref extends Fake implements PdfDocumentRef;

class _Controller extends Fake implements PdfViewerController {
  new(this.count);

  final int count;

  @override
  int get pageCount => count;
}

void main() {
  group('PdfView', () {
    test('turns off what leads out of the document', () {
      final params = _params();

      // No link handler: a link in a document goes nowhere.
      expect(params.linkHandlerParams, isNull);
      expect(params.linkWidgetBuilder, isNull);
      expect(params.annotationRenderingMode, PdfAnnotationRenderingMode.none);
    });

    test('turns off the text selection, so the text cannot be copied out', () {
      expect(_params().textSelectionParams?.enabled, isFalse);
    });

    test('draws no progress and no error of its own', () {
      final params = _params();

      expect(params.backgroundColor, AppColors.documentBackdrop);
      expect(params.loadingBannerBuilder, isNotNull);
      expect(params.errorBannerBuilder, isNotNull);
    });

    test('reports that the file was read, with its page count', () {
      final loaded = <int>[];
      final params = _params(onLoaded: loaded.add);

      params.onViewerReady!(_Document(12), PdfViewerController());

      expect(loaded, [12]);
    });

    test('reports the page the reader is on', () {
      final changes = <(int, int)>[];
      final params = _params(
        onPageChanged: (page, count) => changes.add((page, count)),
        controller: _Controller(12),
      );

      params.onPageChanged!(3);
      params.onPageChanged!(null);

      expect(changes, [(3, 12)]);
    });

    test('reports that the file could not be read, and nothing of why', () {
      var failures = 0;
      final params = _params(onFailed: () => failures += 1);

      params.onDocumentLoadFinished!(_Ref(), true);
      params.onDocumentLoadFinished!(_Ref(), false);

      expect(failures, 1);
    });
  });
}
