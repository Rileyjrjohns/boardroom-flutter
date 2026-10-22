import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/shared/validation.dart';

/// About a century: far above any duration the app uses, far below what an
/// `Instant` can hold.
const int _maxDurationMillis = 3153600000000;

/// A length of time, as a whole, non-negative number of milliseconds. An `int`
/// at runtime (an extension type).
///
/// The specification calls this type `Duration`; it is `DurationMillis` in Dart
/// because `Duration` is a type of `dart:core`.
///
/// It can only be made by [durationFromMillis].
extension type const DurationMillis._(int _millis) implements int;

/// Validates [millis]: a whole number from 0 to 3153600000000.
Result<DurationMillis, ValidationError> durationFromMillis(num millis) => map(
  requireIntegerInRange(
    ValidationField.duration,
    millis,
    0,
    _maxDurationMillis,
  ),
  DurationMillis._,
);
