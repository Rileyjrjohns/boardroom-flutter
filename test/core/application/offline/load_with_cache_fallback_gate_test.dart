import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/application/offline/load_with_cache_fallback.dart';
import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/session_gate.dart';
import 'package:boardroom/core/application/ports/types/session_refusal.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/fake_clock.dart';
import '../../../support/fakes/fake_monitoring.dart';

// The offline policy asks the session through a port of the core, and knows
// nothing of what a session is. These tests give it a gate of their own, with
// refusals of their own, to say what the policy does with each answer; the
// policy with the session of `auth` behind the gate is tested in
// load_with_cache_fallback_test.dart.

/// A refusal that no feature of the app knows.
final class _TestRefusal extends AppError {
  const new();

  @override
  String get code => 'someoneElse';
}

const AppError _someoneElse = _TestRefusal();

final UserId _owner = aUserId();

/// A gate that answers as scripted and records what it was asked.
final class _Gate implements SessionGate {
  new([Result<UserId, SessionRefusal>? answer])
    : _answer = answer ?? ok(_owner);

  final Result<UserId, SessionRefusal> _answer;
  final List<UserId> required = [];
  final List<UserId> ended = [];
  int purged = 0;

  @override
  Future<Result<UserId, SessionRefusal>> requireSameUser(UserId expected) {
    required.add(expected);
    return Future.value(_answer);
  }

  @override
  Future<void> endRefusedSession(UserId user) async {
    ended.add(user);
  }

  @override
  Future<void> purgeSessionData() async {
    purged += 1;
  }
}

final class _Deps implements CacheFallbackDeps {
  new(this.sessionGate);

  @override
  final SessionGate sessionGate;

  @override
  final Clock clock = FakeClock();

  @override
  final Monitoring monitoring = FakeMonitoring();

  @override
  final DurationMillis maxCacheAge = aDuration(3600000);
}

/// A source that fetches `fetched` and counts what is done to the cache.
final class _Source {
  new(Result<String, RepositoryError> fetched, {bool removeFails = false}) {
    source = CacheFallbackSource<String, RepositoryError>(
      resource: CacheResource.meeting,
      attributes: const {},
      fetch: () async => fetched,
      save: (value, cachedAt) async {
        saved += 1;
        return ok<void>(null);
      },
      read: () async => ok(null),
      remove: () {
        removed += 1;
        return Future.value(
          removeFails ? err(storageWriteFailed()) : ok<void>(null),
        );
      },
      revoke: () {
        revoked += 1;
        return Future.value(
          removeFails ? err(storageWriteFailed()) : ok<void>(null),
        );
      },
    );
  }

  late final CacheFallbackSource<String, RepositoryError> source;
  int saved = 0;
  int removed = 0;
  int revoked = 0;
}

void main() {
  group('loadWithCacheFallback, over a session gate of the core', () {
    test('asks the gate whether the user who asked is still the one signed '
        'in, once the remote source has answered', () async {
      final gate = _Gate();
      final source = _Source(ok('remote'));

      final result = await loadWithCacheFallback(
        _Deps(gate),
        _owner,
        source.source,
      );

      expect(gate.required, equals([_owner]));
      expect(isOk(result) ? unwrap(result).data : null, equals('remote'));
      expect(source.saved, equals(1));
    });

    test('returns the error of the refusal as it is, with its own type, and '
        'saves nothing', () async {
      final gate = _Gate(
        err(const SessionRefusal(error: _someoneElse, sessionKept: false)),
      );
      final source = _Source(ok('remote'));

      final result = await loadWithCacheFallback(
        _Deps(gate),
        _owner,
        source.source,
      );

      expect(result, equals(err(_someoneElse)));
      expect(source.saved, equals(0));
    });

    test('empties what the session left when the data was fetched and the '
        'user is gone: nothing points at what the source kept', () async {
      final gate = _Gate(
        err(const SessionRefusal(error: _someoneElse, sessionKept: false)),
      );

      await loadWithCacheFallback(
        _Deps(gate),
        _owner,
        _Source(ok('remote')).source,
      );

      expect(gate.purged, equals(1));
    });

    test('leaves what the session left alone when the session is kept, and '
        'waits for the user to come back', () async {
      final gate = _Gate(
        err(const SessionRefusal(error: _someoneElse, sessionKept: true)),
      );

      await loadWithCacheFallback(
        _Deps(gate),
        _owner,
        _Source(ok('remote')).source,
      );

      expect(gate.purged, equals(0));
    });

    test(
      'empties nothing when the remote call failed: it kept nothing',
      () async {
        final gate = _Gate(
          err(const SessionRefusal(error: _someoneElse, sessionKept: false)),
        );

        final result = await loadWithCacheFallback(
          _Deps(gate),
          _owner,
          _Source(err(networkUnavailable())).source,
        );

        expect(result, equals(err(_someoneElse)));
        expect(gate.purged, equals(0));
      },
    );

    test('has the gate end the session when the server refuses it, and '
        'returns the refusal', () async {
      final gate = _Gate();

      final result = await loadWithCacheFallback(
        _Deps(gate),
        _owner,
        _Source(err(unauthorized())).source,
      );

      expect(result, equals(err(unauthorized())));
      expect(gate.ended, equals([_owner]));
      expect(gate.purged, equals(0));
    });

    test('drops the entry when the server refuses the item, and has the gate '
        'empty everything if that fails', () async {
      final gate = _Gate();
      final source = _Source(err(notFound()), removeFails: true);

      final result = await loadWithCacheFallback(
        _Deps(gate),
        _owner,
        source.source,
      );

      expect(result, equals(err(notFound())));
      expect(source.revoked, equals(1));
      expect(gate.purged, equals(1));
    });

    test('does not touch the session for a fault of the server', () async {
      final gate = _Gate();

      await loadWithCacheFallback(
        _Deps(gate),
        _owner,
        _Source(err(unexpected())).source,
      );

      expect(gate.ended, isEmpty);
      expect(gate.purged, equals(0));
    });
  });
}
