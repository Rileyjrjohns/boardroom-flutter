import 'package:boardroom/app/composition/retryable_codes.dart';
import 'package:boardroom/core/presentation/errors/error_catalog.dart';
import 'package:boardroom/features/auth/presentation/error_messages.dart';

/// What the screens know of the failures of the app, put together: the texts of
/// the failures of the core and of the session (`auth` declares the second, the
/// core the first), and which codes a second try can fix (what the core and the
/// features each say of their own codes, assembled in `retryable_codes.dart`).
/// The core and the features declare what they say; this is the one place that
/// sees them all, and the shared components read it through
/// `errorCatalogProvider`.
///
/// A feature with failures of its own that other screens can meet adds its map
/// here; a failure only its own screen tells (the codes of the document screen,
/// the vote failures) stays in that feature's map.
ErrorCatalog createAppErrorCatalog() => ErrorCatalog(
  messages: {...coreErrorMessages, ...sessionErrorMessages},
  isRetryableCode: isRetryableCode,
);
