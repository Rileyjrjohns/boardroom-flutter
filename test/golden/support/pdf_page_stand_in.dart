import 'package:boardroom/features/documents/presentation/components/pdf_view_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

// Test support, not production code: what a golden shows in place of the PDF
// view (the real one needs the PDF engine of a device). It answers the screen
// the way the real view does once the file is read, and draws a white page with
// grey lines for the text, so that the image shows the watermark laid over a
// page.

/// The pages of the document the stand-in pretends to read.
const int standInPageCount = 12;

/// The override that mounts the stand-in in place of the PDF view.
Override get pdfPageStandInOverride => pdfViewBuilderProvider.overrideWithValue(
  (request) => _PdfPageStandIn(request: request),
);

class _PdfPageStandIn extends StatefulWidget {
  const new({required this.request});

  final PdfViewRequest request;

  @override
  State<_PdfPageStandIn> createState() => _PdfPageStandInState();
}

class _PdfPageStandInState extends State<_PdfPageStandIn> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.request
        ..onLoaded(standInPageCount)
        ..onPageChanged(1, standInPageCount);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE5E7EB),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var line = 0; line < 22; line += 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: FractionallySizedBox(
                      widthFactor: line % 5 == 4 ? 0.6 : 1,
                      child: const SizedBox(
                        height: 8,
                        child: ColoredBox(color: Color(0xFFD1D5DB)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
