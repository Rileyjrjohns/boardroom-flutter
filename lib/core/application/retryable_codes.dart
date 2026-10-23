import 'package:boardroom/core/domain/errors/app_error.dart';

/// The errors of the core that a second try can fix: the network may be back, a
/// server fault may have passed, a store may be readable again. Every other
/// code says something that asking again will not change: the session is gone
/// or refused (`unauthorized`), the item is refused to the user or does not
/// exist (`forbidden`, `notFound`), the request itself is wrong (`validation`).
///
/// A feature has codes of its own, and says for each of them whether a second
/// try can fix it (the documents declare `documentsRetryableCodes`). The core
/// does not know them: the composition assembles the set the screens use (see
/// `retryableCodes` in `lib/app/composition/retryable_codes.dart`).
final Set<String> coreRetryableCodes = Set.unmodifiable({
  RepositoryErrorCode.networkUnavailable.value,
  RepositoryErrorCode.unexpected.value,
  StorageErrorCode.readFailed.value,
});
