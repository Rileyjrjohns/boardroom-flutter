import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'fake_monitoring.freezed.dart';

/// A line logged: its level, its event and its attributes (`null` when the
/// call gave none).
@freezed
abstract class LogRecord with _$LogRecord {
  /// Creates a record.
  const factory({
    required LogLevel level,
    required MonitoringEvent event,
    required LogAttributes? attributes,
  }) = _LogRecord;
}

/// An error captured: its event, the error and its attributes (`null` when the
/// call gave none).
@freezed
abstract class ErrorRecord with _$ErrorRecord {
  /// Creates a record.
  const factory({
    required MonitoringEvent event,
    required AppError error,
    required LogAttributes? attributes,
  }) = _ErrorRecord;
}

/// Keeps what it is given, so that a test can check what a use case reported.
class FakeMonitoring implements Monitoring {
  /// Every line logged, in order.
  final List<LogRecord> logs = [];

  /// Every error captured, in order.
  final List<ErrorRecord> errors = [];

  @override
  void log(LogLevel level, MonitoringEvent event, [LogAttributes? attributes]) {
    logs.add(LogRecord(level: level, event: event, attributes: attributes));
  }

  @override
  void captureError(
    MonitoringEvent event,
    AppError error, [
    LogAttributes? attributes,
  ]) {
    errors.add(ErrorRecord(event: event, error: error, attributes: attributes));
  }

  /// The events logged so far, in order.
  List<MonitoringEvent> loggedEvents() => [
    for (final record in logs) record.event,
  ];

  /// The events whose error was captured so far, in order.
  List<MonitoringEvent> capturedEvents() => [
    for (final record in errors) record.event,
  ];
}
