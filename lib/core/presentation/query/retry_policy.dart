import 'dart:math';

import 'package:boardroom/core/presentation/errors/error_catalog.dart';
import 'package:boardroom/core/presentation/query/query_failure.dart';

/// How many times a failed query is tried again before it is reported.
const int maxQueryRetries = 2;

/// The first wait before a retry, doubled each time.
const Duration retryBaseDelay = Duration(milliseconds: 500);

/// The longest wait before a retry.
const Duration retryMaxDelay = Duration(seconds: 4);

/// Told why, when a failure ends the session: the code, and the epoch of the
/// access the failing action started under when it said (an action does; a
/// query does not).
typedef SessionEndedCallback = void Function(String code, int? startedUnder);

/// The retry rules of the queries (the Riverpod counterpart of `retryPolicy`
/// and `createQueryClient` of the React Native app). It is the `retry`
/// argument of the root `ProviderScope`: Riverpod calls it each time a
/// provider fails, with the number of retries so far.
///
/// - A failure whose code a second try cannot fix is reported at once. Which
///   codes those are is for the catalog to say (`isRetryableCode`).
/// - At most [maxQueryRetries] retries, after 0.5 s then 1 s (doubling,
///   capped at [retryMaxDelay]).
/// - A failure that ends the session ends it for the whole app, through
///   [onSessionEnded], and is reported at once, whichever screen met it.
/// - A thrown value that is not the failure of a use case is read as
///   `unexpected` and retried like a server fault, unless it is an `Error`
///   (a programming error such as a provider nobody overrode), which is
///   reported at once.
/// - Actions are never retried: they are not providers.
final class RetryPolicy {
  /// Creates the policy over the [catalog]; [isSessionEndingCode] is the rule
  /// of `auth` (`isSessionEndingCode`), handed over by the composition.
  const new({
    required this.catalog,
    required this.isSessionEndingCode,
    this.onSessionEnded,
    this.baseDelay = retryBaseDelay,
    this.maxDelay = retryMaxDelay,
  });

  /// What the screens know of the failures.
  final ErrorCatalog catalog;

  /// Whether a failure with this code says the session of the user is over.
  final bool Function(String code) isSessionEndingCode;

  /// Told when a failure ends the session.
  final SessionEndedCallback? onSessionEnded;

  /// The first wait; a test gives [Duration.zero].
  final Duration baseDelay;

  /// The longest wait.
  final Duration maxDelay;

  /// The wait before the next try, or null to report the failure.
  Duration? call(int retryCount, Object error) {
    if (error is Error) {
      return null;
    }
    final code = errorCodeOf(error, catalog);
    if (isSessionEndingCode(code)) {
      onSessionEnded?.call(
        code,
        error is QueryFailure ? error.startedUnder : null,
      );
      return null;
    }
    if (retryCount >= maxQueryRetries || !catalog.isRetryableCode(code)) {
      return null;
    }
    return delayOf(retryCount);
  }

  /// Exponential backoff: 0.5 s, then 1 s, up to 4 s.
  Duration delayOf(int retryCount) {
    final millis = baseDelay.inMilliseconds * pow(2, retryCount).toInt();
    return Duration(milliseconds: min(millis, maxDelay.inMilliseconds));
  }
}
