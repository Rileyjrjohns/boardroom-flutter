import 'package:boardroom/core/domain/errors/app_error.dart';

/// The errors that a second try can fix: the network may be back, a server
/// fault may have passed, a store may be readable again, and the platform may
/// manage to protect the screen next time (`screenProtectionFailed`: a document
/// is opened by an action and not by a query, but its screen offers the same
/// button). Every other code says something that asking again will not change:
/// the session is gone or refused (`unauthorized`, `notAuthenticated`,
/// `sessionExpired`), the app is locked until the user unlocks it
/// (`appLocked`), somebody else is signed in now (`sessionChanged`), the item
/// is refused to the user or does not exist (`forbidden`, `notFound`), the
/// request itself is wrong (`validation`), the platform cannot protect a screen
/// at all (`screenProtectionUnsupported`).
final Set<String> retryableCodes = Set.unmodifiable({
  RepositoryErrorCode.networkUnavailable.value,
  RepositoryErrorCode.unexpected.value,
  StorageErrorCode.readFailed.value,
  ScreenProtectionErrorCode.failed.value,
});

/// Whether asking again can fix a failure with this [code].
bool isRetryableCode(String code) => retryableCodes.contains(code);
