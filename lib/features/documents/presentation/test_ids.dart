// The test ids of the document viewer, declared by the feature that owns the
// screens and put together with the others by `lib/app/test_ids.dart`. Pure
// Dart, so that the conformance test of the specification can read them. The
// widgets set them as `Key(id)`; the values are the ones of
// docs/spec/screens.md.

/// The test ids of the document viewer.
abstract final class DocumentsTestIds {
  /// The viewer is mounted.
  static const String documentScreen = 'document-screen';

  /// The parameter is invalid.
  static const String documentNotFound = 'document-not-found';

  /// The document is being opened.
  static const String documentLoading = 'document-loading';

  /// Opening the document failed.
  static const String documentError = 'document-error';

  /// The title of the opened document.
  static const String documentTitle = 'document-title';

  /// The document is protected.
  static const String documentProtectedBadge = 'document-protected-badge';

  /// The PDF view is mounted.
  static const String documentPdf = 'document-pdf';

  /// The file is being read.
  static const String documentPdfLoading = 'document-pdf-loading';

  /// The viewer could not read the file.
  static const String documentPdfError = 'document-pdf-error';

  /// The page indicator.
  static const String documentPageIndicator = 'document-page-indicator';

  /// The watermark overlay.
  static const String documentWatermark = 'document-watermark';

  /// One tile of the watermark.
  static const String documentWatermarkTile = 'document-watermark-tile';

  /// The secure container of the pages.
  static const String documentSecureContent = 'document-secure-content';

  /// A capture was reported.
  static const String documentCaptureNotice = 'document-capture-notice';

  /// The dismiss button of the capture notice.
  static const String documentCaptureDismiss = 'document-capture-dismiss';
}
