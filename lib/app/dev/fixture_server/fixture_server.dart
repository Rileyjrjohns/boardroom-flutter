import 'dart:convert';
import 'dart:math';

import 'package:boardroom/app/dev/fixture_server/fixture_server_adapter.dart';
import 'package:boardroom/app/dev/fixture_server/mock_api.dart';
import 'package:boardroom/app/dev/in_memory/fixtures/load_fixtures.dart';
import 'package:boardroom/app/dev/in_memory/in_memory_auth_session.dart';
import 'package:boardroom/app/dev/in_memory/in_memory_backend.dart';
import 'package:boardroom/app/dev/in_memory/seed.dart';
import 'package:boardroom/app/dev/in_memory/simulated_network.dart';
import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/core/infrastructure/clock/sleep.dart';
import 'package:boardroom/core/infrastructure/clock/system_clock.dart';
import 'package:boardroom/core/infrastructure/shared/valid.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:meta/meta.dart';

// The fixture server: the simulated server of the app behind the routes of
// docs/api.md, reachable through dio. It is what the development build talks to
// (the counterpart of the mock configuration of the React Native app, whose
// tests reach `MockApi` through MSW), and what the tests of the HTTP adapters
// talk to.

export 'package:boardroom/app/dev/fixture_server/api_message.dart';
export 'package:boardroom/app/dev/fixture_server/fixture_server_adapter.dart';
export 'package:boardroom/app/dev/fixture_server/mock_api.dart';
export 'package:boardroom/app/dev/in_memory/in_memory_backend.dart';
export 'package:boardroom/app/dev/in_memory/seed.dart';
export 'package:boardroom/app/dev/in_memory/simulated_network.dart';

const int _millisPerHour = 3600000;

/// A working day, like the development configuration of the app.
final DurationMillis defaultSessionLifetime = valid(
  durationFromMillis(8 * _millisPerHour),
);

/// Long enough to see a loading state, short enough not to get in the way.
final DurationMillis defaultLatency = valid(durationFromMillis(200));

/// How many random bytes a token is made of.
const int _tokenBytes = 32;

/// A token nobody can guess: random bytes from the secure generator, written in
/// a URL-safe alphabet (visible ASCII, no padding).
String randomToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(_tokenBytes, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// Why the fixture server cannot be built. The detail names a place in a
/// fixture or a rule of the content, never a value.
@immutable
final class FixtureServerError {
  /// Creates the error.
  const new({required this.detail});

  /// What is wrong.
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is FixtureServerError && other.detail == detail;

  @override
  int get hashCode => detail.hashCode;

  @override
  String toString() => 'FixtureServerError($detail)';
}

/// Nobody is the caller of a request that does not name one: every request of
/// the API names its own (see `MockApi`).
final class _Nobody implements Caller {
  const new();

  @override
  Future<Result<Session?, StorageReadFailedError>> current() =>
      Future.value(ok<Session?>(null));
}

/// The simulated server with its API and the dio adapter in front of it. Give
/// [adapter] to a `Dio` (`dio.httpClientAdapter = server.adapter`) and the HTTP
/// adapters of the app talk to the fixtures.
final class FixtureServer {
  const new _({
    required this.api,
    required this.backend,
    required this.accounts,
    required this.adapter,
  });

  /// Builds the server: the seed made of the fixtures shifted to [clock], the
  /// simulated server holding it, its API, and the adapter. Returns the reason
  /// when the fixtures or the options are not acceptable, and never throws.
  ///
  /// The fixtures are the files of the app (its assets) unless [files] gives
  /// others. The [sleep] waits for the simulated latency; the tests give one
  /// that does not wait. The [generateToken] makes the tokens of the sessions;
  /// by default random ones.
  static Future<Result<FixtureServer, FixtureServerError>> create({
    Clock clock = const SystemClock(),
    DurationMillis? latency,
    DurationMillis? sessionLifetime,
    Sleep sleep = timerSleep,
    String Function() generateToken = randomToken,
    FixtureFiles? files,
    RequestLogger? onRequest,
  }) async {
    final now = clock.now();
    final seed = files == null
        ? await buildSeed(now)
        : loadFixtures(files, now);
    final SeedData content;
    switch (seed) {
      case Ok(:final value):
        content = value;
      case Err(:final error):
        return err(FixtureServerError(detail: error.detail));
    }

    final network = SimulatedNetwork(
      sleep: sleep,
      latency: latency ?? defaultLatency,
    );
    final backend = InMemoryBackend.create(
      InMemoryBackendOptions(
        clock: clock,
        auth: const _Nobody(),
        network: network,
        content: content.content,
      ),
    );
    final InMemoryBackend server;
    switch (backend) {
      case Ok(:final value):
        server = value;
      case Err(:final error):
        return err(FixtureServerError(detail: error.code.value));
    }

    final api = MockApi(
      MockApiOptions(
        backend: server,
        clock: clock,
        accounts: content.accounts,
        sessionLifetime: sessionLifetime ?? defaultSessionLifetime,
        generateToken: generateToken,
      ),
    );
    return ok(
      FixtureServer._(
        api: api,
        backend: server,
        accounts: content.accounts,
        adapter: FixtureServerAdapter(api, logger: onRequest),
      ),
    );
  }

  /// The routes of docs/api.md.
  final MockApi api;

  /// The simulated server behind them. Its `network` is the connectivity of the
  /// server: cut it and every request is answered 503.
  final InMemoryBackend backend;

  /// The accounts a client can sign in with, with the password of the
  /// simulation (`demoPassword`).
  final List<DemoAccount> accounts;

  /// The dio adapter that serves the requests from the API.
  final FixtureServerAdapter adapter;
}
