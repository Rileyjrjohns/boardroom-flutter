import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/shared/validation.dart';
import 'package:boardroom/domain/value_objects/duration.dart';

/// The largest number of milliseconds a `DateTime` can hold. An [Instant] never
/// exceeds it, so `DateTime.fromMillisecondsSinceEpoch(instant)` is always a
/// valid date for the presentation to format.
const int _maxEpochMillis = 8640000000000000;

/// A point in time, as a whole number of milliseconds since the Unix epoch, in
/// UTC. An `int` at runtime (an extension type, so no object is allocated):
/// immutable, comparable with the usual operators, and serializable as is. The
/// domain never formats it and has no time zone: both belong to the
/// presentation.
///
/// It can only be made by [parseInstant], the one place that vouches for the
/// raw number.
extension type const Instant._(int _epochMillis) implements int;

/// Validates [epochMillis]: a whole number from 0 to 8640000000000000.
Result<Instant, ValidationError> parseInstant(num epochMillis) => map(
  requireIntegerInRange(
    ValidationField.instant,
    epochMillis,
    0,
    _maxEpochMillis,
  ),
  Instant._,
);

/// Whether [instant] is strictly earlier than [other].
bool isBefore(Instant instant, Instant other) => instant < other;

/// The instant is [other], or later.
bool isAtOrAfter(Instant instant, Instant other) => instant >= other;

/// The instant [duration] after [instant]. Fails only when the result would
/// leave the supported range.
Result<Instant, ValidationError> plus(
  Instant instant,
  DurationMillis duration,
) => parseInstant(instant + duration);

/// Milliseconds from [from] to [to]. Negative when [to] is earlier than [from].
int millisBetween(Instant from, Instant to) => to - from;
