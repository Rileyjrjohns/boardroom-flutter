import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/constants.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/infrastructure/secure_storage/secure_storage.dart';
import 'package:boardroom/infrastructure/shared/attempt.dart';

/// Why the local data was reset.
enum ResetReason implements StableValue {
  /// The key was not in the keychain, and a database was: it could not be
  /// opened.
  keyLost('keyLost'),

  /// The keychain had a key, and it did not open the database.
  keyRejected('keyRejected');

  new(this.value);

  @override
  final String value;
}

/// The record that local data was reset, kept in the secure storage, which a
/// reset of the database does not touch. It is written before anything is set
/// aside and stays until the user has been told ([clearLocalDataReset]), so
/// that an app that stops in the middle of a reset, or that is closed before
/// the user sees the notice, tells them at the next start.
///
/// It holds the reason and nothing else. Its absence is the normal case.
Future<bool> markLocalDataReset(
  SecureStorage storage,
  ResetReason reason,
  int timeoutMillis,
) async {
  final written = await attempt(
    () => storage.set(SecureStorageKey.localDataReset.value, reason.value),
    timeoutMillis,
  );
  return written is Ok;
}

/// Whether local data was reset and the user has not been told. A keychain that
/// cannot be read is captured and counts as no: the notice is an extra, and the
/// start does not wait on it.
Future<bool> hasLocalDataReset(
  SecureStorage storage,
  Monitoring monitoring,
  int timeoutMillis,
) async {
  final read = await attempt(
    () => storage.get(SecureStorageKey.localDataReset.value),
    timeoutMillis,
  );
  switch (read) {
    case Err(:final error):
      monitoring.captureError(
        MonitoringEvent.resetNoticeUnreadable,
        storageReadFailed(error.cause),
      );
      return false;
    case Ok(:final value):
      return value != null;
  }
}

/// Forgets that local data was reset, once the user has been told. Whether it
/// worked is told.
Future<bool> clearLocalDataReset(
  SecureStorage storage,
  int timeoutMillis,
) async {
  final removed = await attempt(
    () => storage.remove(SecureStorageKey.localDataReset.value),
    timeoutMillis,
  );
  return removed is Ok;
}

/// How long the keychain may take to answer about the record before the start
/// goes on without it.
const int _noticeTimeoutMillis = 5000;

/// What the app tells the user about a reset of its local data, and the means
/// to say it was told.
abstract interface class LocalDataResetNotice {
  /// Whether local data was reset and the user has not been told yet.
  bool get pending;

  /// The user has been told: the record is cleared, and they will not be told
  /// again. A record that cannot be cleared is captured, and the user is told
  /// again at the next start. Never throws.
  Future<void> acknowledge();
}

final class _ResetNotice implements LocalDataResetNotice {
  new(
    this._storage,
    this._monitoring,
    this._timeoutMillis, {
    required this.pending,
  });

  final SecureStorage _storage;
  final Monitoring _monitoring;
  final int _timeoutMillis;

  @override
  final bool pending;

  @override
  Future<void> acknowledge() async {
    if (!await clearLocalDataReset(_storage, _timeoutMillis)) {
      _monitoring.captureError(
        MonitoringEvent.resetNoticeNotCleared,
        storageWriteFailed(),
      );
    }
  }
}

/// Reads the record once, at the start, and gives the notice that follows from
/// it.
Future<LocalDataResetNotice> readLocalDataResetNotice(
  SecureStorage storage,
  Monitoring monitoring, [
  int timeoutMillis = _noticeTimeoutMillis,
]) async => _ResetNotice(
  storage,
  monitoring,
  timeoutMillis,
  pending: await hasLocalDataReset(storage, monitoring, timeoutMillis),
);
