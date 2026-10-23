import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';

/// What [isUnlockRequired] needs to decide.
final class AppLockInput {
  /// Creates the input of [isUnlockRequired].
  const new({
    required this.backgroundedAt,
    required this.now,
    required this.gracePeriod,
    required this.hasSession,
  });

  /// When the app went to the background.
  final Instant backgroundedAt;

  /// The current instant.
  final Instant now;

  /// How long the app may stay in the background without asking for the
  /// biometrics again.
  final DurationMillis gracePeriod;

  /// Whether a user is signed in.
  final bool hasSession;
}

/// Must the user unlock the app with the biometrics on returning from the
/// background?
///
/// - Without a session there is nothing to protect: no.
/// - Once the grace period has elapsed (a grace period of zero locks every
///   time): yes.
/// - When `now` is earlier than the instant the app went to the background, the
///   clock has been set back and the time away cannot be known: yes. The rule
///   fails closed.
bool isUnlockRequired(AppLockInput input) {
  if (!input.hasSession) {
    return false;
  }
  if (isBefore(input.now, input.backgroundedAt)) {
    return true;
  }
  return millisBetween(input.backgroundedAt, input.now) >= input.gracePeriod;
}
