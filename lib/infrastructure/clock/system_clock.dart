import 'package:boardroom/application/ports/clock.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/infrastructure/shared/valid.dart';

/// Reads the clock of the device, in milliseconds since the Unix epoch.
typedef ReadMillis = num Function();

/// The reading of the clock of the device.
int _readSystemClock() => DateTime.now().millisecondsSinceEpoch;

/// What a device whose clock reads before 1970 or nonsense is taken to say.
final Instant _epoch = valid(parseInstant(0));

/// The clock of the device. The only production code that reads the system
/// time, which is why the domain and the application cannot (a lint rule
/// forbids it there). `now()` never fails: a fractional reading is truncated,
/// and one that is not an instant at all (a clock set before 1970, a
/// non-finite value) reads as the epoch, instead of throwing.
final class SystemClock implements Clock {
  /// Creates a clock that reads the time through [readMillis], the time of the
  /// device by default.
  const new([ReadMillis readMillis = _readSystemClock])
    : _readMillis = readMillis;

  final ReadMillis _readMillis;

  @override
  Instant now() {
    final reading = _readMillis();
    final whole = reading.isFinite ? reading.truncate() : 0;
    final parsed = parseInstant(whole < 0 ? 0 : whole);
    return switch (parsed) {
      Ok(:final value) => value,
      Err() => _epoch,
    };
  }
}
