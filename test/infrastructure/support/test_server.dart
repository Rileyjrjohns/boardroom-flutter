import 'package:boardroom/domain/value_objects/credentials.dart';
import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:boardroom/infrastructure/clock/sleep.dart';
import 'package:boardroom/infrastructure/files/file_store.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_auth_session.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_backend.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_document_repository.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_meeting_repository.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_vote_repository.dart';
import 'package:boardroom/infrastructure/in_memory/simulated_network.dart';

import '../../application/support/fake_clock.dart';
import '../../application/support/fake_monitoring.dart';
import '../../domain/support/builders.dart';
import 'memory_file_volume.dart';
import 'sleep.dart';

// Test support, not production code: the simulated server of the tests, wired
// by hand the way the composition root wires the real one, with a clock that
// only moves when the test says so and a network that does not wait. Only tests
// and other test support import it.

/// The password of the accounts of the test server.
const String testPassword = 'test-password';

/// What the session of a test lasts.
final DurationMillis testSessionLifetime = aDuration(millisPerHour);

/// What a test chooses about its server.
final class TestServerOptions {
  /// Creates the options. By default the server holds the meeting of
  /// [aMeetingWithAgenda] and nothing recorded, waits for no latency, has
  /// `user-1` signed in, and keeps the downloads in memory.
  const new({this.content, this.sleep, this.signedIn = true, this.files});

  /// What the server holds.
  final ServerContent? content;

  /// How the latency is waited for. By default, not at all.
  final Sleep? sleep;

  /// Whether `user-1` is signed in at first.
  final bool signedIn;

  /// Where the downloads of the documents are kept.
  final FileStore? files;
}

/// What the user of an account types to sign in.
Credentials credentialsOf(DemoAccount account) =>
    Credentials(email: account.user.email, password: account.password);

/// The two accounts of the test server: `user-1` (Alice) and `user-2` (Bruno).
List<DemoAccount> testAccounts() => [
  DemoAccount(user: aUser(), password: testPassword),
  DemoAccount(
    user: aUser(
      id: aUserId('user-2'),
      fullName: 'Bruno Durand',
      email: anEmail('bruno@example.com'),
    ),
    password: testPassword,
  ),
];

/// The simulated server of a test, with what a test reaches into.
final class TestServer {
  /// Creates the description of a server.
  const new({
    required this.clock,
    required this.network,
    required this.accounts,
    required this.auth,
    required this.backend,
    required this.files,
    required this.monitoring,
    required this.meetings,
    required this.documents,
    required this.votes,
  });

  /// The clock of the server and of the device.
  final FakeClock clock;

  /// The connectivity of the server.
  final SimulatedNetwork network;

  /// `user-1` (Alice) and `user-2` (Bruno).
  final List<DemoAccount> accounts;

  /// The session of the device.
  final InMemoryAuthSession auth;

  /// The server.
  final InMemoryBackend backend;

  /// Where the downloads of the documents are kept.
  final FileStore files;

  /// What the adapters of the device report.
  final FakeMonitoring monitoring;

  /// The meetings of the server, as the device reaches them.
  final InMemoryMeetingRepository meetings;

  /// The documents of the server, as the device reaches them.
  final InMemoryDocumentRepository documents;

  /// The votes of the server, as the device reaches them.
  final InMemoryVoteRepository votes;

  /// Replaces what the server holds. A content the server refuses is a broken
  /// fixture.
  void load(ServerContent content) => unwrap(backend.replaceContent(content));
}

/// A server for a test.
TestServer createTestServer([TestServerOptions options = const .new()]) {
  final clock = FakeClock();
  final network = SimulatedNetwork(
    sleep: options.sleep ?? immediateSleep,
    latency: aDuration(0),
  );
  final accounts = testAccounts();
  final auth = InMemoryAuthSession(
    clock: clock,
    network: network,
    accounts: accounts,
    sessionLifetime: testSessionLifetime,
  );
  if (options.signedIn) {
    auth.openSessionFor(accounts.first.user);
  }

  final backend = unwrap(
    InMemoryBackend.create(
      InMemoryBackendOptions(
        clock: clock,
        auth: AuthSessionCaller(auth),
        network: network,
        content:
            options.content ??
            ServerContent(
              meetings: [aMeetingWithAgenda()],
              recordedVotes: const [],
            ),
      ),
    ),
  );
  final files = options.files ?? createFileStore(MemoryFileVolume());
  final monitoring = FakeMonitoring();
  return TestServer(
    clock: clock,
    network: network,
    accounts: accounts,
    auth: auth,
    backend: backend,
    files: files,
    monitoring: monitoring,
    meetings: InMemoryMeetingRepository(backend),
    documents: InMemoryDocumentRepository(backend, files, monitoring),
    votes: InMemoryVoteRepository(backend),
  );
}
