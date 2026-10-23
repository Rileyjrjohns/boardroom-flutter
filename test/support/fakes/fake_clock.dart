import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';

import '../builders/builders.dart' as builders;

/// A clock that only moves when the test says so.
class FakeClock implements Clock {
  /// Starts at [initial], or at the instant of the tests.
  new([Instant? initial]) : _current = initial ?? builders.now;

  Instant _current;

  @override
  Instant now() => _current;

  /// Puts the clock at [instant].
  // ignore: use_setters_to_change_properties
  void set(Instant instant) {
    _current = instant;
  }

  /// Moves the clock forward by [millis], which may be negative.
  void advance(int millis) {
    _current = builders.after(_current, millis);
  }
}
