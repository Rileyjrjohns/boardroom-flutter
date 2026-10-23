import 'package:boardroom/app/composition/ports.dart';
import 'package:boardroom/app/composition/settings.dart';
import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/app/container/container_error.dart';
import 'package:boardroom/app/container/monitoring.dart';
import 'package:boardroom/app/container/runtime.dart';
import 'package:boardroom/app/container/wiring.dart';
import 'package:boardroom/app/device/create_device_platform.dart';
import 'package:boardroom/app/device/device_platform.dart';
import 'package:boardroom/app/persistence/boardroom_database.dart';
import 'package:boardroom/app/persistence/migrations.dart';
import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/clock/system_clock.dart';
import 'package:boardroom/core/infrastructure/connectivity/device_connectivity.dart';
import 'package:boardroom/core/infrastructure/files/create_device_file_store.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/core/infrastructure/http/http_client.dart';
import 'package:boardroom/core/infrastructure/persistence/local_data_reset.dart';
import 'package:boardroom/core/infrastructure/persistence/protected_database.dart';
import 'package:boardroom/core/presentation/notices/app_notices.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/infrastructure/biometrics/device_biometric_gate.dart';
import 'package:boardroom/features/auth/infrastructure/http_auth_session.dart';
import 'package:boardroom/features/auth/infrastructure/session_vault.dart';
import 'package:boardroom/features/documents/infrastructure/drift_document_cache.dart';
import 'package:boardroom/features/documents/infrastructure/http_document_repository.dart';
import 'package:boardroom/features/documents/infrastructure/native/native_screen_protection.dart';
import 'package:boardroom/features/documents/infrastructure/native/pigeon_screen_protection_module.dart';
import 'package:boardroom/features/meetings/infrastructure/drift_meeting_cache.dart';
import 'package:boardroom/features/meetings/infrastructure/http_meeting_repository.dart';
import 'package:boardroom/features/votes/infrastructure/drift_vote_outbox.dart';
import 'package:boardroom/features/votes/infrastructure/http_vote_repository.dart';

/// What the files of the documents are called in the logs.
const String _documentsResource = 'document';

/// The cancel label of the prompt of the biometrics when the runtime hands over
/// no function that reads the translations: the stable name of the button. The
/// app always hands one over, so a user never sees this one.
const String defaultCancelLabel = 'cancel';

/// The text of the prompt of the biometrics when the runtime hands over no
/// function that reads the translations: the stable names of the reason and of
/// the cancel button. See [defaultCancelLabel].
PromptText defaultPromptText(BiometricReason reason) =>
    PromptText(message: reason.value, cancelLabel: defaultCancelLabel);

/// The notices of the real configuration: what was read from the keychain at
/// the start, and the means to say the user was told.
final class _LocalDataNotices implements AppNotices {
  const new(this._notice);

  final LocalDataResetNotice _notice;

  @override
  bool get localDataReset => _notice.pending;

  @override
  Future<void> acknowledgeLocalDataReset() => _notice.acknowledge();
}

/// The adapters of the real configuration, wired to each other:
///
/// - the three remote repositories and the sign-in talk to the API through one
///   `HttpClient`, which reads the token of the signed-in user from the
///   `SessionVault` (the secure storage of the device) when it creates each
///   request;
/// - the cache of meetings, the cache of documents and the outbox of votes live
///   in one local database, encrypted with a key that only the secure storage
///   holds (`openProtectedDatabase`). Opening it is asynchronous and can fail,
///   which is why the container is built asynchronously;
/// - when opening the database had to set an unreadable one aside, the notice
///   that the user is owed is read from the secure storage and handed over with
///   the ports;
/// - the biometrics are those of the device, and the connectivity that of the
///   network state of the platform;
/// - the key of the database is drawn from the secure random generator of the
///   device (`platform.randomBytes`);
/// - the screen protection is the one the runtime hands over (the app owns the
///   plugin and gives the native one), else the native adapter over the plugin;
/// - the cache of documents is in the same database for the metadata and in
///   files of the device for the content, which the repository downloads to;
///   the files no entry points at are deleted when it starts.
Future<Result<Wiring, ContainerError>> createHttpPorts(
  HttpConfiguration config,
  ContainerRuntime runtime,
) async {
  final clock = runtime.clock ?? const SystemClock();
  final monitoring =
      runtime.monitoring ??
      createMonitoring(config.sentryDsn, sdk: runtime.sentrySdk);
  final platform = runtime.platform ?? await createDevicePlatform();
  // Found before the database is opened: a folder that cannot be had must not
  // leave a database open.
  final files = runtime.fileStore ?? await createDeviceFileStore();

  final opened = await openProtectedDatabase<BoardroomDatabase>(
    ProtectedDatabaseOptions<BoardroomDatabase>(
      opener: platform.databaseOpener,
      storage: platform.secureStorage,
      randomBytes: platform.randomBytes,
      monitoring: monitoring,
      name: databaseName,
      migrations: migrations,
      databaseFactory: createBoardroomDatabase,
    ),
  );
  final BoardroomDatabase database;
  switch (opened) {
    case Ok(:final value):
      database = value;
    case Err(:final error):
      return err(storageUnavailable(error.reason));
  }

  try {
    return ok(
      await _wireOver(
        database,
        config: config,
        runtime: runtime,
        platform: platform,
        files: files,
        clock: clock,
        monitoring: monitoring,
      ),
    );
    // Whatever the rest of the wiring throws, the database that was opened is
    // closed before the failure goes on to the container.
  } catch (_) {
    await database.close();
    rethrow;
  }
}

/// The ports over the open [database].
Future<Wiring> _wireOver(
  BoardroomDatabase database, {
  required HttpConfiguration config,
  required ContainerRuntime runtime,
  required DevicePlatform platform,
  required FileStore files,
  required Clock clock,
  required Monitoring monitoring,
}) async {
  final reset = await readLocalDataResetNotice(
    platform.secureStorage,
    monitoring,
  );

  final vault = SessionVault(
    storage: platform.secureStorage,
    monitoring: monitoring,
  );
  final client = HttpClient(
    HttpClientOptions(
      baseUrl: config.baseUrl,
      timeout: config.requestTimeout,
      tokens: vault,
      monitoring: monitoring,
      adapter: runtime.httpAdapter,
    ),
  );
  final documentCache = DriftDocumentCache(
    DriftDocumentCacheOptions(
      database: database,
      files: files,
      monitoring: monitoring,
    ),
  );
  // The files that no entry points at (a download whose entry was never saved,
  // a file that was being written when the app stopped) are deleted before
  // anything can be downloaded. A sweep that fails is reported once, as in the
  // development configuration, and what it left waits for the next start.
  final swept = await documentCache.sweepOrphans();
  if (swept case Err(:final error)) {
    monitoring.captureError(MonitoringEvent.orphanFileNotDeleted, error, {
      LogAttribute.resource: _documentsResource,
    });
  }

  return Wiring(
    ports: Ports(
      clock: clock,
      monitoring: monitoring,
      auth: HttpAuthSession(
        HttpAuthSessionOptions(
          client: client,
          vault: vault,
          clock: clock,
          monitoring: monitoring,
        ),
      ),
      biometricGate: DeviceBiometricGate(
        api: platform.localAuthentication,
        promptText: runtime.biometricPromptText ?? defaultPromptText,
        monitoring: monitoring,
        allowDevicePasscode: config.allowDevicePasscode,
      ),
      connectivity: DeviceConnectivity(
        api: platform.networkState,
        monitoring: monitoring,
      ),
      // A build without the native module cannot protect a screen, and the
      // adapter says so: a confidential document is then not shown, which is
      // the safe way to fail.
      screenProtection:
          runtime.screenProtection ??
          NativeScreenProtection(
            module: loadScreenProtectionModule(),
            monitoring: monitoring,
          ),
      meetings: HttpMeetingRepository(client, monitoring),
      meetingCache: DriftMeetingCache(
        database: database,
        monitoring: monitoring,
      ),
      documents: HttpDocumentRepository(
        client,
        monitoring,
        files,
        HttpDocumentRepositoryOptions(downloadTimeout: documentDownloadTimeout),
      ),
      documentCache: documentCache,
      votes: HttpVoteRepository(client, monitoring),
      outbox: DriftVoteOutbox(database: database, monitoring: monitoring),
    ),
    // A real start is a cold start: whoever the stored session belongs to
    // unlocks the app first.
    startsLocked: true,
    notices: _LocalDataNotices(reset),
    onDispose: database.close,
  );
}
