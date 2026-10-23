import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/session_data_purger.dart';

/// What [purgeCaches] needs.
abstract interface class PurgeCachesDeps {
  /// Everything a session leaves on the device, one purger for each feature
  /// that keeps data for a user. They are purged in this order, and the
  /// composition decides it.
  List<SessionDataPurger> get sessionDataPurgers;

  /// Where a failed purge is reported.
  Monitoring get monitoring;
}

/// Empties what a session leaves on the device (the meeting cache and the
/// document cache, the content of the documents included), for every owner,
/// through the [SessionDataPurger] of each feature. Called when a session ends,
/// so that nothing a user saw stays on the device. Every purger is always
/// attempted, whatever the one before it did. A failure is captured and never
/// returned: it must not stop a user from signing out.
Future<void> purgeCaches(PurgeCachesDeps deps) async {
  final PurgeCachesDeps(:sessionDataPurgers, :monitoring) = deps;

  for (final purger in sessionDataPurgers) {
    final purged = await purger.purge();
    if (purged case Err(:final error)) {
      monitoring.captureError(MonitoringEvent.cachePurgeFailed, error, {
        LogAttribute.resource: purger.resource.value,
      });
    }
  }
}
