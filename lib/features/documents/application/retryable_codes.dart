import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';

/// The errors of the documents that a second try can fix: the platform may
/// manage to protect the screen next time (`screenProtectionFailed`: a document
/// is opened by an action and not by a query, but its screen offers the same
/// button). The platform that cannot protect a screen at all
/// (`screenProtectionUnsupported`) will not be able to the next time either.
///
/// The composition adds them to those of the core (see `retryableCodes` in
/// `lib/app/composition/retryable_codes.dart`).
final Set<String> documentsRetryableCodes = Set.unmodifiable({
  ScreenProtectionErrorCode.failed.value,
});
