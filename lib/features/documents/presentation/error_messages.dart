import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/errors/error_catalog.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/l10n/app_localizations.dart';

// The domain and the application speak in codes (an error code, a kind of
// capture) and carry no text. These maps are where a code of the documents
// becomes a text. A test checks that every code of the family has an entry.

/// What the screen of a document says when it cannot show it.
/// `networkUnavailable` is told apart on purpose: opening a document is the
/// one place where it means the document is not on the device, so the user is
/// told why it cannot be read offline and not just that the server is out of
/// reach. A document that does not exist or that the user may not have is told
/// as a document, not as a meeting.
final Map<String, ErrorMessage> documentErrorMessages = Map.unmodifiable({
  AuthenticationErrorCode.notAuthenticated.value: (AppLocalizations l) =>
      l.coreErrorsNotAuthenticated,
  AuthenticationErrorCode.sessionExpired.value: (AppLocalizations l) =>
      l.coreErrorsSessionExpired,
  AuthenticationErrorCode.appLocked.value: (AppLocalizations l) =>
      l.coreErrorsAppLocked,
  AuthenticationErrorCode.sessionChanged.value: (AppLocalizations l) =>
      l.coreErrorsSessionChanged,
  StorageErrorCode.readFailed.value: (AppLocalizations l) =>
      l.coreErrorsStorageReadFailed,
  RepositoryErrorCode.networkUnavailable.value: (AppLocalizations l) =>
      l.documentsDocumentErrorsNetworkUnavailable,
  RepositoryErrorCode.unauthorized.value: (AppLocalizations l) =>
      l.coreErrorsUnauthorized,
  RepositoryErrorCode.forbidden.value: (AppLocalizations l) =>
      l.documentsDocumentErrorsForbidden,
  RepositoryErrorCode.notFound.value: (AppLocalizations l) =>
      l.documentsDocumentNotFound,
  RepositoryErrorCode.unexpected.value: (AppLocalizations l) =>
      l.coreErrorsUnexpected,
  ScreenProtectionErrorCode.unsupported.value: (AppLocalizations l) =>
      l.documentsDocumentErrorsScreenProtectionUnsupported,
  ScreenProtectionErrorCode.failed.value: (AppLocalizations l) =>
      l.documentsDocumentErrorsScreenProtectionFailed,
});

/// The text of the failure of an open, `unexpected` for a code with none.
String documentErrorMessage(AppLocalizations l10n, String code) =>
    (documentErrorMessages[code] ??
    documentErrorMessages[RepositoryErrorCode.unexpected.value]!)(l10n);

/// What the screen of a document says when the system reports a capture. The
/// end of a recording says nothing new (the capture was told when it began and
/// the notice stays), so it has no text.
String? captureNoticeMessage(
  AppLocalizations l10n,
  ScreenCaptureKind kind,
) => switch (kind) {
  ScreenCaptureKind.screenshotTaken => l10n.documentsDocumentCaptureScreenshot,
  ScreenCaptureKind.recordingStarted => l10n.documentsDocumentCaptureRecording,
  ScreenCaptureKind.recordingStopped => null,
};
