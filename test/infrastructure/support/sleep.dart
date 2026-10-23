import 'package:boardroom/infrastructure/clock/sleep.dart';

// Test support, not production code: a test never waits for a simulated
// latency. Only tests and other test support import it.

/// A sleep that does not wait: the simulated network answers as fast as the
/// code runs.
Future<void> immediateSleep(int millis) => Future.value();

/// A sleep that does not wait either, and remembers how long it was asked to
/// wait.
({Sleep sleep, List<int> requested}) recordingSleep() {
  final requested = <int>[];
  return (
    requested: requested,
    sleep: (millis) {
      requested.add(millis);
      return Future.value();
    },
  );
}
