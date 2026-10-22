import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:boardroom/domain/value_objects/instant.dart';

/// May a cached entry still be shown as stale data? Yes while it is no older
/// than [maxAge]: an entry of exactly that age is still good, one millisecond
/// older is not. An entry dated in the future (the clock of the device was set
/// back since it was stored) cannot be dated at all, so it is not trusted: the
/// rule fails closed.
bool isWithinMaxAge(Instant cachedAt, Instant now, DurationMillis maxAge) {
  final age = millisBetween(cachedAt, now);
  return age >= 0 && age <= maxAge;
}
