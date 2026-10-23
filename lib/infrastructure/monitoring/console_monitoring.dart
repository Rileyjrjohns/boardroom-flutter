import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/errors/app_error.dart';

/// What a console must offer for the monitoring to write to it.
abstract interface class ConsoleSink {
  /// Writes an information.
  void info(List<Object?> data);

  /// Writes a warning.
  void warn(List<Object?> data);

  /// Writes an error.
  void error(List<Object?> data);
}

/// The word a line starts with for each channel of the sink. The process has
/// one standard output, which cannot tell the three channels apart, so the line
/// says which one it was written to; the development tools can then be searched
/// for the warnings and the errors.
const String _infoTag = 'info';
const String _warnTag = 'warn';
const String _errorTag = 'error';

/// The console of the process: every channel is a line on the standard output
/// of the Dart zone it runs in, so that the development tools show it. The line
/// starts with the name of its channel, as `console.info`, `console.warn` and
/// `console.error` are told apart by the tools of React Native.
final class PrintConsoleSink implements ConsoleSink {
  /// Creates the console of the process.
  const new();

  @override
  void info(List<Object?> data) => _write(_infoTag, data);

  @override
  void warn(List<Object?> data) => _write(_warnTag, data);

  @override
  void error(List<Object?> data) => _write(_errorTag, data);

  void _write(String channel, List<Object?> data) {
    // The console is the whole point of this adapter.
    // ignore: avoid_print
    print('$channel ${data.join(' ')}');
  }
}

/// Starts every line, so that the app can be picked out of the noise of the
/// development tools.
const String logPrefix = '[boardroom]';

/// Monitoring for development and for the demo: structured events written to
/// the console. The events and attribute names are the enumerations of the
/// port, so the lines can be searched; the errors carry their code and
/// structured fields, which hold no personal data (see the errors). A
/// production adapter wraps a crash reporter instead and replaces this one in
/// the composition root.
///
/// Fire and forget, as the port requires: nothing is returned, nothing waits,
/// and nothing throws, whatever the console does.
final class ConsoleMonitoring implements Monitoring {
  /// Creates monitoring that writes to [sink], the console of the process by
  /// default.
  const new([ConsoleSink sink = const PrintConsoleSink()]) : _sink = sink;

  final ConsoleSink _sink;

  @override
  void log(LogLevel level, MonitoringEvent event, [LogAttributes? attributes]) {
    try {
      final data = [logPrefix, event.value, _namedAttributes(attributes)];
      // Typed over every level: a level added to the port without a channel
      // fails the analysis here, instead of being dropped.
      switch (level) {
        case LogLevel.info:
          _sink.info(data);
        case LogLevel.warn:
          _sink.warn(data);
      }
      // Monitoring must never break the code it observes.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }

  @override
  void captureError(
    MonitoringEvent event,
    AppError error, [
    LogAttributes? attributes,
  ]) {
    try {
      _sink.error([
        logPrefix,
        event.value,
        error,
        _namedAttributes(attributes),
      ]);
      // Monitoring must never break the code it observes.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }

  Map<String, Object> _namedAttributes(LogAttributes? attributes) => {
    for (final MapEntry(:key, :value) in (attributes ?? const {}).entries)
      key.value: value,
  };
}
