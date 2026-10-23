import 'dart:async';
import 'dart:typed_data';

import 'package:boardroom/infrastructure/files/file_store.dart';
import 'package:boardroom/infrastructure/fixture_server/fixture_server_adapter.dart';
import 'package:boardroom/infrastructure/fixture_server/mock_api.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_auth_session.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_backend.dart';
import 'package:boardroom/infrastructure/in_memory/simulated_network.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../application/support/fake_clock.dart';
import '../../application/support/fake_monitoring.dart';
import '../../domain/support/builders.dart';
import 'test_server.dart';

// Test support, not production code: the HTTP adapters talking to the simulated
// server through the dio adapter that stands in for the network (the
// counterpart of MSW in the React Native tests). `installFixtureServer` is
// called once, at the top of a test file; `createHttpServerSide` builds a
// server for one test.

/// The address the tests give to the API. Nothing listens there: the adapter
/// answers for it.
const String testApiUrl = 'http://api.boardroom.test';

/// How the network behaves for the clients of a test, which a test changes
/// while it runs.
final class NetworkConditions {
  /// Whether the device has a connection. Without one, a request fails the way
  /// a request without a network does (a connection error).
  bool online = true;

  /// How long the server waits before it answers.
  int delayMillis = 0;

  /// A server that never answers.
  bool neverAnswers = false;

  /// Back to a connected device and a server that answers at once.
  void reset() {
    online = true;
    delayMillis = 0;
    neverAnswers = false;
  }
}

/// What a test makes the server send instead of the API.
typedef ServerOverride = FutureOr<ResponseBody> Function(
  RequestOptions options,
);

/// The API a test file has installed, and the world that answers for it now. It
/// is the `HttpClientAdapter` the clients of the test are given.
final class InstalledFixtureServer implements HttpClientAdapter {
  /// The API of the world created last.
  MockApi? api;

  /// How the network behaves now.
  final NetworkConditions conditions = NetworkConditions();

  /// The requests the server received, in order, as `METHOD url`.
  final List<String> received = [];

  /// The headers of each request the server received, in the same order.
  final List<Map<String, String>> receivedHeaders = [];

  /// Answers the next requests itself instead of the API, while set: a server
  /// that sends what the API never would (a wrong media type, a file that is
  /// not one, a body that never ends). Reset after each test.
  ServerOverride? answerWith;

  /// Forgets what the last test did.
  void reset() {
    conditions.reset();
    received.clear();
    receivedHeaders.clear();
    answerWith = null;
  }

  /// The header [name] of the request number [index] the server received,
  /// whatever its case.
  String? receivedHeader(int index, String name) {
    final wanted = name.toLowerCase();
    for (final entry in receivedHeaders[index].entries) {
      if (entry.key.toLowerCase() == wanted) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (options.uri.origin != Uri.parse(testApiUrl).origin) {
      // Nothing may reach a real network by mistake.
      throw StateError('a request went to ${options.uri.origin}');
    }
    received.add('${options.method} ${options.uri}');
    receivedHeaders.add({
      for (final entry in options.headers.entries)
        entry.key: entry.value is Iterable
            ? (entry.value as Iterable).join(', ')
            : '${entry.value}',
    });
    return boundedByRequest(
      _answer(options, requestStream),
      options,
      cancelFuture,
    );
  }

  Future<ResponseBody> _answer(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) async {
    if (!conditions.online) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no connection',
      );
    }
    if (conditions.neverAnswers) {
      await Completer<void>().future;
    }
    if (conditions.delayMillis > 0) {
      await Future<void>.delayed(
        Duration(milliseconds: conditions.delayMillis),
      );
    }
    final replacement = answerWith;
    if (replacement != null) {
      return await replacement(options);
    }
    final served = api;
    if (served == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no server',
      );
    }
    return await FixtureServerAdapter(served)
        .fetch(options, requestStream, null);
  }

  @override
  void close({bool force = false}) {}
}

/// Installs the fixture server for the test file that calls it, and resets it
/// after each test. Call it at the top of `main`.
InstalledFixtureServer installFixtureServer() {
  final installed = InstalledFixtureServer();
  tearDown(installed.reset);
  return installed;
}

/// The server behind the API: the simulated server of the tests with the routes
/// of `MockApi` on it. Nobody is signed in at first, and the accounts are those
/// of the test server (`user-1`, Alice, and `user-2`, Bruno). The clock is the
/// one of the test server, so that a session expires for the server and, when
/// the device shares it, for the device too.
final class HttpServerSide {
  /// Creates the description of a server behind the API.
  const new({required this.server, required this.api, required this.accounts});

  /// The simulated server of the test.
  final TestServer server;

  /// The routes of the API on it.
  final MockApi api;

  /// The accounts that can sign in. A test adds to it.
  final List<DemoAccount> accounts;

  /// The clock of the server and of the device.
  FakeClock get clock => server.clock;

  /// The connectivity of the server.
  SimulatedNetwork get network => server.network;

  /// The server.
  InMemoryBackend get backend => server.backend;

  /// Where the downloads of the documents are kept.
  FileStore get files => server.files;

  /// What the adapters of the device report.
  FakeMonitoring get monitoring => server.monitoring;

  /// Replaces what the server holds.
  void load(ServerContent content) => server.load(content);
}

/// The server behind the API (see [HttpServerSide]), announced to [installed].
HttpServerSide createHttpServerSide(
  InstalledFixtureServer installed, [
  TestServerOptions options = const .new(),
]) {
  final server = createTestServer(
    TestServerOptions(
      content: options.content,
      sleep: options.sleep,
      signedIn: false,
      files: options.files,
    ),
  );
  final accounts = [...server.accounts];
  var tokens = 0;
  final api = MockApi(
    MockApiOptions(
      backend: server.backend,
      clock: server.clock,
      accounts: accounts,
      sessionLifetime: aDuration(millisPerHour),
      generateToken: () {
        tokens += 1;
        return 'token-$tokens';
      },
    ),
  );
  installed.api = api;
  return HttpServerSide(server: server, api: api, accounts: accounts);
}
