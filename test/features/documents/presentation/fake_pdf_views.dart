import 'package:boardroom/features/documents/presentation/components/pdf_view_builder.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

// Test support, not production code: what the tests give the screen in place of
// the PDF view (the real one needs the PDF engine of a device). The fake is a
// plain widget that records the request it was last given and lets a test
// report what the real view would: that the file was read, that the page
// changed, that it failed. The same way the React Native tests stub
// `react-native-pdf`.

/// The fake PDF views of one test.
final class FakePdfViews {
  /// The request of the view on the screen, as it was last built, or nothing
  /// when no view is mounted.
  PdfViewRequest? latest;

  /// How many views were mounted, over the whole test.
  int mounted = 0;

  _FakePdfViewState? _active;

  /// The request of the view on the screen, or a failure of the test.
  PdfViewRequest get request =>
      latest ?? (throw StateError('No PDF view is on the screen.'));

  /// The override that puts the fake in place of the real view.
  Override get override => pdfViewBuilderProvider.overrideWithValue(
    (request) => _FakePdfView(this, request),
  );
}

class _FakePdfView extends StatefulWidget {
  const new(this.views, this.request);

  final FakePdfViews views;
  final PdfViewRequest request;

  @override
  State<_FakePdfView> createState() => _FakePdfViewState();
}

class _FakePdfViewState extends State<_FakePdfView> {
  @override
  void initState() {
    super.initState();
    widget.views
      .._active = this
      ..mounted += 1;
  }

  @override
  void dispose() {
    final views = widget.views;
    if (views._active == this) {
      views
        .._active = null
        ..latest = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.views.latest = widget.request;
    return const SizedBox.expand();
  }
}
