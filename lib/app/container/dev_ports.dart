import 'package:boardroom/app/composition/ports.dart';
import 'package:boardroom/app/composition/settings.dart';
import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/app/container/container_error.dart';
import 'package:boardroom/app/container/monitoring.dart';
import 'package:boardroom/app/container/runtime.dart';
import 'package:boardroom/app/container/wiring.dart';
import 'package:boardroom/app/dev/fixture_server/fixture_server.dart';
import 'package:boardroom/app/dev/in_memory/in_memory_biometric_gate.dart';
import 'package:boardroom/app/dev/in_memory/in_memory_secure_storage.dart';
import 'package:boardroom/app/dev/in_memory/simulated_connectivity.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/clock/sleep.dart';
import 'package:boardroom/core/infrastructure/clock/system_clock.dart';
import 'package:boardroom/core/infrastructure/files/create_device_file_store.dart';
import 'package:boardroom/core/infrastructure/http/http_client.dart';
import 'package:boardroom/core/presentation/demo/demo_controls.dart';
import 'package:boardroom/core/presentation/notices/app_notices.dart';
import 'package:boardroom/features/auth/domain/value_objects/credentials.dart';
import 'package:boardroom/features/auth/infrastructure/http_auth_session.dart';
import 'package:boardroom/features/auth/infrastructure/session_vault.dart';
import 'package:boardroom/features/documents/infrastructure/http_document_repository.dart';
import 'package:boardroom/features/documents/infrastructure/in_memory_document_cache.dart';
import 'package:boardroom/features/documents/infrastructure/in_memory_screen_protection.dart';
import 'package:boardroom/features/meetings/infrastructure/http_meeting_repository.dart';
import 'package:boardroom/features/meetings/infrastructure/in_memory_meeting_cache.dart';
import 'package:boardroom/features/votes/infrastructure/http_vote_repository.dart';
import 'package:boardroom/features/votes/infrastructure/in_memory_vote_outbox.dart';

/// The address the development configuration gives its client. Nothing listens
/// there: the adapter of the fixture server answers for every request, and the
/// reserved `.invalid` top-level domain cannot resolve, so a request that ever
/// escaped the adapter would fail instead of reaching a real host.
const String devApiBaseUrl = 'https://api.boardroom.invalid';

/// What the files of the documents are called in the logs.
const String _documentsResource = 'document';

/// What the connection of the simulated server is for the demo: the
/// `NetworkControl` of the server, seen through the narrow interface of the
/// demo components.
final class _DemoNetworkOf implements DemoNetwork {
  const new(this._network);

  final NetworkControl _network;

  @override
  bool get online => _network.online;

  @override
  void setOnline({required bool online}) {
    _network.setOnline(online: online);
  }

  @override
  Unsubscribe subscribe(void Function({required bool online}) listener) =>
      _network.subscribe(listener);
}

/// The adapters of the development configuration, wired to each other. They are
/// the real HTTP adapters (the client, the sign-in over the session vault, and
/// the three repositories) running over the adapter of the fixture server,
/// which answers the routes of docs/api.md from the simulated server in
/// process: what runs in development is what runs in production, with only the
/// network replaced. The session is kept by the same vault, over a storage in
/// memory. The caches and the outbox are in memory (the content of the
/// documents is in files of the device, written by the repository), the
/// biometrics always succeed, and the connectivity is that of the simulated
/// network, so that its offline switch drives the whole app. The seed is not
/// generated: it is loaded from the frozen fixtures of docs/spec/fixtures, with
/// every date shifted by whole days to the clock (see `buildSeed`), so there
/// are always upcoming and past meetings.
///
/// The screen protection is the one the runtime hands over (the app gives the
/// native one), else the simulation, which records what it is asked and can be
/// made to report a capture.
///
/// When the configuration starts signed in, the first account of the simulation
/// signs in through the sign-in of the auth adapter, as if the user had just
/// done it, and the app starts unlocked.
Future<Result<Wiring, ContainerError>> createDevPorts(
  DevConfiguration config,
  ContainerRuntime runtime,
) async {
  final clock = runtime.clock ?? const SystemClock();
  final monitoring =
      runtime.monitoring ??
      createMonitoring(config.sentryDsn, sdk: runtime.sentrySdk);

  final created = await FixtureServer.create(
    clock: clock,
    latency: config.latency,
    sessionLifetime: config.sessionLifetime,
    sleep: runtime.sleep ?? timerSleep,
    files: runtime.fixtureFiles,
  );
  final FixtureServer server;
  switch (created) {
    case Ok(:final value):
      server = value;
    case Err(:final error):
      return err(mockDataInvalid(error.detail));
  }

  final files = runtime.fileStore ?? await createDeviceFileStore();
  // The documents already viewed are remembered in memory in this
  // configuration, and forgotten when the app stops; their files are not.
  // Whatever the last run left is deleted before anything can be downloaded, so
  // that no content stays on the device with nothing pointing at it.
  final swept = await files.deleteAll();
  if (swept case Err(:final error)) {
    monitoring.captureError(
      MonitoringEvent.orphanFileNotDeleted,
      storageWriteFailed(error.cause),
      {LogAttribute.resource: _documentsResource},
    );
  }

  final vault = SessionVault(
    storage: InMemorySecureStorage(),
    monitoring: monitoring,
  );
  final client = HttpClient(
    HttpClientOptions(
      baseUrl: devApiBaseUrl,
      timeout: httpRequestTimeout,
      tokens: vault,
      monitoring: monitoring,
      adapter: server.adapter,
    ),
  );
  final auth = HttpAuthSession(
    HttpAuthSessionOptions(
      client: client,
      vault: vault,
      clock: clock,
      monitoring: monitoring,
    ),
  );

  if (config.startSignedIn) {
    final opened = await _signInFirstAccount(server, auth);
    if (opened != null) {
      return err(opened);
    }
  }

  return ok(
    Wiring(
      ports: Ports(
        clock: clock,
        monitoring: monitoring,
        auth: auth,
        biometricGate: InMemoryBiometricGate(),
        connectivity: SimulatedConnectivity(server.backend.network),
        screenProtection:
            runtime.screenProtection ?? InMemoryScreenProtection(),
        meetings: HttpMeetingRepository(client, monitoring),
        meetingCache: InMemoryMeetingCache(),
        documents: HttpDocumentRepository(
          client,
          monitoring,
          files,
          HttpDocumentRepositoryOptions(
            downloadTimeout: documentDownloadTimeout,
          ),
        ),
        documentCache: InMemoryDocumentCache(files),
        votes: HttpVoteRepository(client, monitoring),
        outbox: InMemoryVoteOutbox(),
      ),
      // A session opened by the configuration itself stands for a sign-in the
      // user has just made: it is unlocked. Without one, the app starts locked,
      // as a cold start does.
      startsLocked: !config.startSignedIn,
      notices: const NoNotices(),
      demoControls: DemoControls(
        network: _DemoNetworkOf(server.backend.network),
        accounts: [
          for (final account in server.accounts)
            DemoAccountHint(
              fullName: account.user.fullName,
              email: account.user.email,
              password: account.password,
            ),
        ],
      ),
    ),
  );
}

/// Signs the first account of the simulation in. Returns the error to start
/// with, or null.
Future<ContainerError?> _signInFirstAccount(
  FixtureServer server,
  HttpAuthSession auth,
) async {
  if (server.accounts.isEmpty) {
    return mockDataInvalid(_noAccount);
  }
  final account = server.accounts.first;
  final signedIn = await auth.signIn(
    Credentials(email: account.user.email, password: account.password),
  );
  if (signedIn case Err(:final error)) {
    return mockDataInvalid(error.code);
  }
  return null;
}

/// The detail of the error of a simulation that has no account to sign in.
const String _noAccount = 'the fixtures hold no account';
