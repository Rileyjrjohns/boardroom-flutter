import 'dart:convert';

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/http/http_client.dart';
import 'package:boardroom/core/infrastructure/secure_storage/secure_storage.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/infrastructure/dto/session_dto.dart';
import 'package:boardroom/features/auth/infrastructure/session_vault.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/builders/names.dart';
import '../../../support/fakes/fake_monitoring.dart';
import '../../../support/infrastructure/memory_secure_storage.dart';

final SignedIn _signedIn = SignedIn(
  token: 'token-of-alice',
  session: aSession(),
);

/// What the vault gives the client for it: the token, with the user it belongs
/// to.
final BearerToken _aliceToken = BearerToken(
  token: 'token-of-alice',
  userId: aUserId(),
);

final SignedIn _bruno = SignedIn(
  token: 'token-of-bruno',
  session: aSession(
    user: aUser(
      id: aUserId('user-2'),
      fullName: 'Bruno Durand',
      email: anEmail('bruno@example.com'),
    ),
    expiresAt: at(7200000),
  ),
);

typedef _Vault = ({
  MemorySecureStorage storage,
  FakeMonitoring monitoring,
  SessionVault vault,
  SessionVault Function() again,
});

_Vault _aVault({int timeoutMillis = 1000, MemorySecureStorage? held}) {
  final storage = held ?? MemorySecureStorage();
  final monitoring = FakeMonitoring();
  SessionVault build() => SessionVault(
    storage: storage,
    monitoring: monitoring,
    timeoutMillis: timeoutMillis,
  );
  return (
    storage: storage,
    monitoring: monitoring,
    vault: build(),
    again: build,
  );
}

Map<String, Object?> _stored(MemorySecureStorage storage) =>
    jsonDecode(storage.snapshot()[SecureStorageKey.session.value] ?? '{}')
        as Map<String, Object?>;

/// Lets what is waiting on the storage and on the timers run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

final class _UndeletableStorage extends MemorySecureStorage {
  @override
  Future<void> remove(String key) => Future.error(StateError('locked'));
}

void main() {
  group('SessionVault', () {
    test('holds nobody at first, which is not an error', () async {
      final (:vault, storage: _, monitoring: _, again: _) = _aVault();

      expect(await vault.session(), equals(ok<Session?>(null)));
      expect(await vault.token(), equals(ok<BearerToken?>(null)));
    });

    test('keeps the session and the token it is given, and gives '
        'the session as it was', () async {
      final (:vault, storage: _, monitoring: _, again: _) = _aVault();

      expect(await vault.replace(_signedIn), equals(ok<void>(null)));

      expect(await vault.session(), equals(ok<Session?>(_signedIn.session)));
      expect(await vault.token(), equals(ok<BearerToken?>(_aliceToken)));
    });

    test('writes one item, so that a session and a token can never '
        'be those of two users', () async {
      final (:vault, :storage, monitoring: _, again: _) = _aVault();

      await vault.replace(_signedIn);
      await vault.replace(_bruno);

      expect(storage.snapshot().keys, equals([SecureStorageKey.session.value]));
      expect(
        _stored(storage),
        equals({
          'token': 'token-of-bruno',
          'user': {
            'id': 'user-2',
            'fullName': 'Bruno Durand',
            'email': 'bruno@example.com',
          },
          'expiresAt': at(7200000),
        }),
      );
    });

    test('finds the session again when the app starts again, '
        'reading the storage once', () async {
      final (:vault, :again, :storage, monitoring: _) = _aVault();
      await vault.replace(_signedIn);
      final readsBefore = storage.getCalls;
      final restarted = again();

      expect(
        await restarted.session(),
        equals(ok<Session?>(_signedIn.session)),
      );
      expect(await restarted.token(), equals(ok<BearerToken?>(_aliceToken)));
      expect(
        await restarted.session(),
        equals(ok<Session?>(_signedIn.session)),
      );

      expect(storage.getCalls - readsBefore, equals(1));
    });

    test('leaves the session as it was when the write fails, in '
        'memory and in the storage', () async {
      final (:vault, :storage, monitoring: _, again: _) = _aVault();
      await vault.replace(_signedIn);
      storage.failNext();

      final failed = await vault.replace(_bruno);

      expect(failed, equals(err(storageWriteFailed('unknown failure'))));
      expect(await vault.session(), equals(ok<Session?>(_signedIn.session)));
      expect(await vault.token(), equals(ok<BearerToken?>(_aliceToken)));
      expect(_stored(storage)['token'], equals('token-of-alice'));
    });

    test(
      'forgets the session and the token, in memory and in the storage',
      () async {
        final (:vault, :storage, :again, monitoring: _) = _aVault();
        await vault.replace(_signedIn);

        expect(await vault.clear(), equals(ok<void>(null)));

        expect(await vault.session(), equals(ok<Session?>(null)));
        expect(await vault.token(), equals(ok<BearerToken?>(null)));
        expect(storage.snapshot(), isEmpty);
        expect(await again().session(), equals(ok<Session?>(null)));
      },
    );

    test('succeeds in clearing when there was nothing to clear', () async {
      final (:vault, storage: _, monitoring: _, again: _) = _aVault();

      expect(await vault.clear(), equals(ok<void>(null)));
      expect(await vault.clear(), equals(ok<void>(null)));
    });

    test('stops using the token at once, and says so, when the '
        'storage cannot forget it, and can try again', () async {
      final (:vault, :storage, monitoring: _, again: _) = _aVault();
      await vault.replace(_signedIn);
      storage.failNext();

      final failed = await vault.clear();

      expect(failed, isA<Err<void, StorageWriteFailedError>>());
      expect(await vault.token(), equals(ok<BearerToken?>(null)));
      expect(await vault.clear(), equals(ok<void>(null)));
      expect(storage.snapshot(), isEmpty);
    });

    test('reports a storage that cannot be read, tries again at the '
        'next call, and does not remember the failure', () async {
      final (:vault, :storage, :again, monitoring: _) = _aVault();
      await vault.replace(_signedIn);
      final restarted = again();
      storage.failNext();

      final failed = await restarted.session();

      expect(failed, isA<Err<Session?, StorageReadFailedError>>());
      expect(await restarted.token(), equals(ok<BearerToken?>(_aliceToken)));
    });

    test('turns a storage that does not answer into a failure '
        'within the time it was given', () async {
      final (:vault, :storage, monitoring: _, again: _) = _aVault(
        timeoutMillis: 20,
      );
      storage.hang();

      expect(await vault.session(), equals(err(storageReadFailed('timeout'))));
      expect(
        await vault.replace(_signedIn),
        equals(err(storageWriteFailed('timeout'))),
      );
      expect(await vault.clear(), equals(err(storageWriteFailed('timeout'))));
    });

    test('runs the operations in the order they were asked, so that '
        'the last sign-in is the session', () async {
      final (:vault, :storage, monitoring: _, again: _) = _aVault();

      await Future.wait([
        vault.replace(_signedIn),
        vault.replace(_bruno),
        vault.clear(),
        vault.replace(_signedIn),
      ]);

      expect(await vault.token(), equals(ok<BearerToken?>(_aliceToken)));
      expect(_stored(storage)['token'], equals('token-of-alice'));
    });

    test('keeps going after an operation failed', () async {
      final (:vault, :storage, monitoring: _, again: _) = _aVault();
      storage.failNext();

      final [failed, succeeded] = await Future.wait([
        vault.replace(_signedIn),
        vault.replace(_bruno),
      ]);

      expect(failed, isA<Err<void, StorageWriteFailedError>>());
      expect(succeeded, isA<Ok<void, StorageWriteFailedError>>());
      expect(
        await vault.token(),
        equals(
          ok<BearerToken?>(
            BearerToken(token: 'token-of-bruno', userId: aUserId('user-2')),
          ),
        ),
      );
    });

    group('an item that no longer reads back', () {
      final valid = jsonEncode({
        'token': 't',
        'user': {
          'id': 'user-1',
          'fullName': 'Alice Martin',
          'email': 'alice@example.com',
        },
        'expiresAt': 1000,
      });

      for (final (name, raw) in [
        ('text that is not JSON', 'not json'),
        ('JSON of another shape', '{"token":"t"}'),
        ('an empty token', valid.replaceFirst('"t"', '""')),
        (
          'a user whose email is not one',
          valid.replaceFirst('alice@example.com', 'nobody'),
        ),
        ('a blank user id', valid.replaceFirst('user-1', ' ')),
        ('an expiry that is not an instant', valid.replaceFirst('1000', '-5')),
        ('an expiry that is text', valid.replaceFirst('1000', '"soon"')),
      ]) {
        test('is treated as nobody signed in for $name: reported, '
            'without its content, and deleted', () async {
          final (:vault, :storage, :monitoring, again: _) = _aVault();
          storage.seed(SecureStorageKey.session.value, raw);

          expect(await vault.session(), equals(ok<Session?>(null)));
          expect(await vault.token(), equals(ok<BearerToken?>(null)));

          expect(storage.snapshot(), isEmpty);
          expect(
            monitoring.errors.map((record) => record.event),
            equals([MonitoringEvent.storedRowDiscarded]),
          );
          expect(
            monitoring.errors.map((record) => record.attributes),
            equals([
              {LogAttribute.resource: 'session'},
            ]),
          );
          expect('${monitoring.errors}', isNot(contains('alice@example.com')));
        });
      }

      test(
        'still answers nobody when the bad item cannot be deleted either',
        () async {
          final storage = _UndeletableStorage()
            ..seed(SecureStorageKey.session.value, 'not json');
          final (:vault, monitoring: _, storage: _, again: _) = _aVault(
            held: storage,
          );

          expect(await vault.session(), equals(ok<Session?>(null)));
        },
      );

      test('reads a valid item', () async {
        final (:vault, :storage, monitoring: _, again: _) = _aVault();
        storage.seed(SecureStorageKey.session.value, valid);

        expect(
          await vault.token(),
          equals(ok<BearerToken?>(BearerToken(token: 't', userId: aUserId()))),
        );
      });
    });
  });

  group('SessionVault, an operation that landed late', () {
    test('does not bring a signed-out session back: a sign-in whose '
        'write times out, a sign-out, then the write lands', () async {
      final (:vault, :storage, monitoring: _, again: _) = _aVault(
        timeoutMillis: 20,
      );
      await vault.replace(_signedIn);
      final land = storage.holdNext();

      final timedOut = await vault.replace(_bruno);
      final signedOut = await vault.clear();
      land();
      await _settle();

      expect(timedOut, isA<Err<void, StorageWriteFailedError>>());
      expect(signedOut, equals(ok<void>(null)));
      expect(storage.snapshot(), isEmpty);
      expect(await vault.session(), equals(ok<Session?>(null)));
    });

    test('does not bring a signed-out session back from a storage '
        'that never held one', () async {
      final (:vault, :storage, :again, monitoring: _) = _aVault(
        timeoutMillis: 20,
      );
      await vault.clear();
      final land = storage.holdNext();

      await vault.replace(_signedIn);
      await vault.clear();
      land();
      await _settle();

      expect(storage.snapshot(), isEmpty);
      expect(await again().session(), equals(ok<Session?>(null)));
    });

    test('does not drop a session that was signed in after a '
        'sign-out whose removal timed out', () async {
      final (:vault, :storage, monitoring: _, again: _) = _aVault(
        timeoutMillis: 20,
      );
      await vault.replace(_signedIn);
      final land = storage.holdNext();

      final timedOut = await vault.clear();
      await vault.replace(_bruno);
      land();
      await _settle();

      expect(timedOut, isA<Err<void, StorageWriteFailedError>>());
      expect(_stored(storage)['token'], equals('token-of-bruno'));
      expect(
        await vault.token(),
        equals(
          ok<BearerToken?>(
            BearerToken(token: 'token-of-bruno', userId: aUserId('user-2')),
          ),
        ),
      );
    });

    test('puts back the session the vault still holds when a write '
        'that failed lands anyway', () async {
      final (:vault, :storage, monitoring: _, again: _) = _aVault(
        timeoutMillis: 20,
      );
      await vault.replace(_signedIn);
      final land = storage.holdNext();

      await vault.replace(_bruno);
      land();
      await _settle();

      expect(_stored(storage)['token'], equals('token-of-alice'));
      expect(await vault.token(), equals(ok<BearerToken?>(_aliceToken)));
    });

    test('keeps the session it holds when the correction of a late '
        'write fails too', () async {
      final (:vault, :storage, monitoring: _, again: _) = _aVault(
        timeoutMillis: 20,
      );
      await vault.replace(_signedIn);
      final land = storage.holdNext();
      await vault.replace(_bruno);
      storage.failNext();

      land();
      await _settle();

      expect(await vault.session(), equals(ok<Session?>(_signedIn.session)));
    });

    test('does not wait for a storage that holds a call for ever: '
        'the next operation still settles', () async {
      final (:vault, :storage, monitoring: _, again: _) = _aVault(
        timeoutMillis: 20,
      );
      storage.holdNext();

      await vault.replace(_signedIn);
      final cleared = await vault.clear();

      expect(cleared, equals(ok<void>(null)));
    });

    test('runs operations in the order they were asked for, even if '
        'the storage answers the first one last', () async {
      final (:vault, :storage, monitoring: _, again: _) = _aVault(
        timeoutMillis: 5000,
      );
      await vault.replace(_signedIn);
      final release = storage.holdNext();
      final callsBefore = storage.setCalls;

      final first = vault.replace(_bruno);
      final second = vault.clear();
      await _settle();
      // The second operation has not touched the storage: it waits for the
      // first.
      expect(storage.setCalls - callsBefore, equals(1));
      expect(storage.removeCalls, equals(0));
      release();

      expect(
        (await Future.wait([first, second]))
            .map((answer) => answer is Ok)
            .toList(),
        equals([true, true]),
      );
      expect(storage.snapshot(), isEmpty);
    });
  });

  group('SessionVault, in Dart', () {
    test('never prints the token', () async {
      final (:vault, storage: _, :monitoring, again: _) = _aVault();
      await vault.replace(_signedIn);

      final token = await vault.token();

      expect(
        '$token ${formatPretty(token)} $monitoring',
        isNot(contains('token-of-alice')),
      );
    });
  });
}
