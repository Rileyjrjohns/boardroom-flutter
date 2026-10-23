import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';
import 'package:boardroom/core/infrastructure/monitoring/console_monitoring.dart';
import 'package:boardroom/core/infrastructure/monitoring/sentry_monitoring.dart';

/// The reason given when an address is configured but the build has no SDK to
/// report with (docs/monitoring.md: the Sentry adapter is written and tested
/// but disabled, the project has no SDK dependency).
const String sentrySdkUnavailable = 'sdkUnavailable';

/// The monitoring of the app, from the address (DSN) of the crash reporter that
/// the build was given (`BOARDROOM_SENTRY_DSN`). Off by default: with no
/// address, or a blank one, the events go to the console, as they do in
/// development. With one, and an [sdk] to report with, they go to Sentry.
///
/// An address that is not valid, an SDK that does not start, or an address with
/// no SDK (the project ships none: docs/monitoring.md) never stops the app:
/// monitoring must not decide whether the app runs. The console stays, and says
/// why once, with the reason and no address (it is not a secret, but it names
/// the project). The [sink] is the console it writes to, for the tests.
Monitoring createMonitoring(
  String? dsn, {
  SentrySdk? sdk,
  ConsoleSink sink = const PrintConsoleSink(),
}) {
  final address = trimText(dsn ?? '');
  final console = ConsoleMonitoring(sink);
  if (address.isEmpty) {
    return console;
  }

  final String reason;
  if (sdk == null) {
    reason = sentrySdkUnavailable;
  } else {
    switch (createSentryMonitoring(address, sdk)) {
      case Ok(:final value):
        return value;
      case Err(:final error):
        reason = error.value;
    }
  }

  console.log(LogLevel.warn, MonitoringEvent.monitoringNotStarted, {
    LogAttribute.reason: reason,
  });
  return console;
}
