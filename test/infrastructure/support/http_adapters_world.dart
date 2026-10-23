import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/infrastructure/files/file_store.dart';
import 'package:boardroom/infrastructure/fixture_server/mock_api.dart';
import 'package:boardroom/infrastructure/http/http_auth_session.dart';
import 'package:boardroom/infrastructure/http/http_client.dart';
import 'package:boardroom/infrastructure/http/http_document_repository.dart';
import 'package:boardroom/infrastructure/http/http_meeting_repository.dart';
import 'package:boardroom/infrastructure/http/http_vote_repository.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_auth_session.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_backend.dart';
import 'package:boardroom/infrastructure/in_memory/simulated_network.dart';
import 'package:boardroom/infrastructure/secure_storage/session_vault.dart';

import '../../application/support/fake_clock.dart';
import '../../application/support/fake_monitoring.dart';
import '../../domain/support/builders.dart';
import 'http_world.dart';
import 'memory_secure_storage.dart';
import 'test_server.dart';

// Test support, not production code: the HTTP adapters of a device that talks
// to the simulated server through the dio adapter that stands in for the
// network (the counterpart of `createHttpWorld` of the React Native tests,
// which reach it through MSW). `createHttpWorld` builds a server and its
// clients for one test, by hand, the way the composition root builds them.

/// What a test chooses about its world.
final class HttpWorldOptions {
  /// Creates the options. By default the server is the one of
  /// [createHttpServerSide], the client waits five seconds and the document
  /// repository has its default limits.
  const new({
    this.server = const .new(),
    this.clientTimeout,
    this.documents = const .new(),
    this.storage,
  });

  /// What the simulated server is made of.
  final TestServerOptions server;

  /// Replaces the timeout of the client, for a test of the timeout.
  final DurationMillis? clientTimeout;

  /// What the document repository is built with: the size cap, the download
  /// timeout.
  final HttpDocumentRepositoryOptions documents;

  /// Where the session is kept, to share it between two devices or to make it
  /// fail.
  final MemorySecureStorage? storage;
}

/// The server behind the API and the HTTP adapters of a device that talks to
/// it.
final class HttpWorld {
  /// Creates the description of a world.
  const new({
    required this.serverSide,
    required this.monitoring,
    required this.storage,
    required this.vault,
    required this.client,
    required this.auth,
    required this.meetings,
    required this.documents,
    required this.votes,
  });

  /// The server behind the API (see [createHttpServerSide]).
  final HttpServerSide serverSide;

  /// What the adapters of the device report.
  final FakeMonitoring monitoring;

  /// The secure storage of the device.
  final MemorySecureStorage storage;

  /// The session of the device and its token.
  final SessionVault vault;

  /// The client of the device.
  final HttpClient client;

  /// Authentication against the API.
  final HttpAuthSession auth;

  /// The meetings of the API.
  final HttpMeetingRepository meetings;

  /// The documents of the API.
  final HttpDocumentRepository documents;

  /// The votes of the API.
  final HttpVoteRepository votes;

  /// The clock of the server and of the device.
  FakeClock get clock => serverSide.clock;

  /// The connectivity of the server.
  SimulatedNetwork get network => serverSide.network;

  /// The server.
  InMemoryBackend get backend => serverSide.backend;

  /// The routes of the API on it.
  MockApi get api => serverSide.api;

  /// Where the downloads of the documents are kept.
  FileStore get files => serverSide.files;

  /// The accounts that can sign in.
  List<DemoAccount> get accounts => serverSide.accounts;

  /// Replaces what the server holds.
  void load(ServerContent content) => serverSide.load(content);

  /// Signs the device in as the user of an account, registering the account if
  /// the server lacks it.
  Future<void> signInAs(UserId userId) async {
    final known = accounts.where((account) => account.user.id == userId);
    final DemoAccount account;
    if (known.isEmpty) {
      account = DemoAccount(
        user: aUser(id: userId, email: anEmail('$userId@example.com')),
        password: testPassword,
      );
      accounts.add(account);
    } else {
      account = known.first;
    }
    await auth.signIn(credentialsOf(account));
  }
}

/// The server behind the API (see [createHttpServerSide]) and the HTTP adapters
/// of a device that talks to it.
HttpWorld createHttpWorld(
  InstalledFixtureServer installed, [
  HttpWorldOptions options = const .new(),
]) {
  final serverSide = createHttpServerSide(installed, options.server);

  final monitoring = FakeMonitoring();
  final storage = options.storage ?? MemorySecureStorage();
  final vault = SessionVault(storage: storage, monitoring: monitoring);
  final client = HttpClient(
    HttpClientOptions(
      baseUrl: testApiUrl,
      timeout: options.clientTimeout ?? aDuration(5000),
      tokens: vault,
      monitoring: monitoring,
      adapter: installed,
    ),
  );
  return HttpWorld(
    serverSide: serverSide,
    monitoring: monitoring,
    storage: storage,
    vault: vault,
    client: client,
    auth: HttpAuthSession(
      HttpAuthSessionOptions(
        client: client,
        vault: vault,
        clock: serverSide.clock,
        monitoring: monitoring,
      ),
    ),
    meetings: HttpMeetingRepository(client, monitoring),
    documents: HttpDocumentRepository(
      client,
      monitoring,
      serverSide.files,
      options.documents,
    ),
    votes: HttpVoteRepository(client, monitoring),
  );
}
