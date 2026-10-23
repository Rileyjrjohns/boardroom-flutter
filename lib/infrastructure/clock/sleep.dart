/// Waits for a number of milliseconds. The only thing in the app that creates a
/// timer for a delay on purpose: the simulated network latency. It is a
/// function handed to the code that needs it, so the domain and the application
/// stay free of timers, and a test replaces it with one that does not wait
/// (`test/infrastructure/support/sleep.dart`).
typedef Sleep = Future<void> Function(int millis);

/// The real thing: completes after [millis] milliseconds of the clock of the
/// device.
Future<void> timerSleep(int millis) =>
    Future<void>.delayed(Duration(milliseconds: millis));
