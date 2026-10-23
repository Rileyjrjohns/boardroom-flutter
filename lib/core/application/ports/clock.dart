import 'package:boardroom/core/domain/value_objects/instant.dart';

/// The only way the domain and the application read the time. Business code
/// never calls `DateTime.now()` (a lint rule forbids it), so every rule that
/// depends on time can be tested with a clock that is set by hand.
abstract interface class Clock {
  /// The current instant, on the clock of the device. Never fails. The device
  /// clock is not trustworthy (the user can set it), which the rules built on
  /// it account for: see the app lock and the cache age in
  /// `docs/spec/domain.md`.
  Instant now();
}
