import 'dart:convert';

import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/entities/session.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/credentials.dart';
import 'package:boardroom/infrastructure/http/http_auth_session.dart';
import 'package:boardroom/infrastructure/http/protocol.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_backend.dart';
import 'package:boardroom/infrastructure/secure_storage/secure_storage.dart';
import 'package:boardroom/infrastructure/secure_storage/session_vault.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../domain/support/builders.dart';
import '../support/http_adapters_world.dart';
import '../support/http_world.dart';
import '../support/memory_secure_storage.dart';
import '../support/test_server.dart';

// What the contract suite cannot say about the HTTP side of the session: what
// is kept on the device, where, and what a refusal of the server becomes. The
// contract suite runs in http_repositories_test.dart.

void main() {
  final installed = installFixtureServer();

  ({HttpWorld world, Credentials alice, Credentials bruno}) aWorld() {
    final world = createHttpWorld(installed);
    final [alice, bruno, ...] = world.accounts;
    return (
      world: world,
      alice: credentialsOf(alice),
      bruno: credentialsOf(bruno),
    );
  }

  /// The server sends [text] with the [status], whatever the request.
  void serverSends(int status, String text) {
    installed.answerWith = (_) => ResponseBody.fromString(
      text,
      status,
      headers: {
        HttpHeader.contentType.value: [mediaTypeJson],
      },
    );
  }

  Matcher storageWriteFailure() => isA<Err<dynamic, dynamic>>().having(
    (result) => result.error,
    'error',
    isA<StorageWriteFailedError>(),
  );

  group('HttpAuthSession', () {
    test('keeps the session and the token in the secure storage, in one '
        'item', () async {
      final (:world, :alice, bruno: _) = aWorld();

      final session = unwrap(await world.auth.signIn(alice));

      final snapshot = world.storage.snapshot();
      final item = jsonDecode(
        snapshot[SecureStorageKey.session.value] ?? '{}',
      ) as Map<String, dynamic>;
      expect(snapshot.keys, equals([SecureStorageKey.session.value]));
      expect(item['token'], isA<String>());
      expect(
        item['user'],
        equals({
          'id': 'user-1',
          'fullName': 'Alice Martin',
          'email': 'alice@example.com',
        }),
      );
      expect(session.expiresAt, equals(item['expiresAt']));
    });

    test('never gives the application the token: the session it returns '
        'holds a user and an expiry only', () async {
      final (:world, :alice, bruno: _) = aWorld();

      final session = unwrap(await world.auth.signIn(alice));

      final item = jsonDecode(
        world.storage.snapshot()[SecureStorageKey.session.value] ?? '{}',
      ) as Map<String, dynamic>;
      expect(session.user, equals(world.accounts.first.user));
      expect(session.expiresAt, isA<int>());
      expect('$session', isNot(contains(item['token'] as String)));
      expect('$session', isNot(contains('token')));
    });

    test('computes the expiry on the clock of the device from the lifetime '
        'the server grants', () async {
      final (:world, :alice, bruno: _) = aWorld();
      world.clock.advance(5000);

      final session = unwrap(await world.auth.signIn(alice));

      expect(session.expiresAt, equals(world.clock.now() + millisPerHour));
    });

    test('is found again by an app that starts again on the same '
        'storage', () async {
      final (:world, :alice, bruno: _) = aWorld();
      final session = await world.auth.signIn(alice);
      final restarted = HttpAuthSession(
        HttpAuthSessionOptions(
          client: world.client,
          vault: SessionVault(
            storage: world.storage,
            monitoring: world.monitoring,
          ),
          clock: world.clock,
          monitoring: world.monitoring,
        ),
      );

      expect(await restarted.current(), equals(session));
    });

    test('leaves the session as it was, and says the storage failed, when '
        'the new session cannot be kept', () async {
      final (:world, :alice, :bruno) = aWorld();
      final first = await world.auth.signIn(alice);
      world.storage.failNext();

      final failed = await world.auth.signIn(bruno);

      expect(failed, storageWriteFailure());
      expect(await world.auth.current(), equals(first));
    });

    test('refuses credentials the server refuses, with invalidCredentials, '
        'and keeps nothing', () async {
      final (:world, :alice, bruno: _) = aWorld();

      final refused = await world.auth.signIn(
        Credentials(email: alice.email, password: '${alice.password}x'),
      );

      expect(refused, equals(err(invalidCredentials())));
      expect(world.storage.snapshot(), isEmpty);
    });

    test('forgets the session on sign-out, from the storage too, without '
        'telling the server', () async {
      final (:world, :alice, bruno: _) = aWorld();
      await world.auth.signIn(alice);
      installed.received.clear();

      expect(await world.auth.signOut(), equals(ok<void>(null)));

      expect(world.storage.snapshot(), isEmpty);
      expect(installed.received, isEmpty);
    });

    test('signs out even when the storage cannot forget, and reports '
        'it', () async {
      final (:world, :alice, bruno: _) = aWorld();
      await world.auth.signIn(alice);
      world.storage.failNext();

      final failed = await world.auth.signOut();

      expect(failed, storageWriteFailure());
      expect(await world.auth.current(), equals(ok<Session?>(null)));
    });

    test('reports a session that cannot be read from the storage', () async {
      final storage = MemorySecureStorage();
      final world = createHttpWorld(
        installed,
        HttpWorldOptions(storage: storage),
      );
      storage.failNext();

      expect(
        await world.auth.current(),
        isA<Err<Session?, StorageReadFailedError>>(),
      );
    });

    group('when the server does not answer as expected', () {
      test('is networkUnavailable without a connection', () async {
        final (:world, :alice, bruno: _) = aWorld();
        installed.conditions.online = false;

        expect(
          await world.auth.signIn(alice),
          equals(err(networkUnavailable())),
        );
        expect(world.storage.snapshot(), isEmpty);
      });

      test('is networkUnavailable when the simulated server is unreachable '
          '(503)', () async {
        final (:world, :alice, bruno: _) = aWorld();
        world.network.setOnline(online: false);

        expect(
          await world.auth.signIn(alice),
          equals(err(networkUnavailable())),
        );
      });

      test('is unexpected, with the status, for a body of the wrong shape, '
          'and reports where', () async {
        final (:world, :alice, bruno: _) = aWorld();
        serverSends(200, '{"accessToken":1}');

        expect(
          await world.auth.signIn(alice),
          equals(err(unexpected('invalid response'))),
        );
        expect(
          world.monitoring.capturedEvents(),
          equals([MonitoringEvent.responseInvalid]),
        );
        expect(
          world.monitoring.errors.single.attributes,
          equals({
            LogAttribute.resource: 'session',
            LogAttribute.issuePaths: 'accessToken',
          }),
        );
      });

      for (final (code, status, cause) in [
        ('forbidden', 403, 'status 403'),
        ('notFound', 404, 'status 404'),
      ]) {
        test('is unexpected for a $code, with $cause as its only '
            'cause', () async {
          final (:world, :alice, bruno: _) = aWorld();
          serverSends(status, '');

          expect(
            await world.auth.signIn(alice),
            equals(err(unexpected(cause))),
          );
        });
      }

      test('is unexpected for a rejection, which sign-in has no use '
          'for', () async {
        final (:world, :alice, bruno: _) = aWorld();
        serverSends(422, '{"error":{}}');

        expect(
          await world.auth.signIn(alice),
          equals(err(unexpected('status 422'))),
        );
      });

      test('is unexpected, and reports the rule broken, when the user the '
          'server describes is not valid', () async {
        final (:world, :alice, bruno: _) = aWorld();
        serverSends(
          200,
          jsonEncode({
            'accessToken': 't',
            'tokenType': 'Bearer',
            'expiresIn': 60,
            'user': {'id': 'user-1', 'fullName': 'Alice', 'email': 'nobody'},
          }),
        );

        final answer = await world.auth.signIn(alice);

        expect(answer, equals(err(unexpected('invalid response'))));
        expect(
          world.monitoring.capturedEvents(),
          equals([MonitoringEvent.responseInvalid]),
        );
        expect(world.storage.snapshot(), isEmpty);
      });
    });

    test('answers every request with the identity read when it was created, '
        'even if somebody signs in meanwhile', () async {
      final (:world, :alice, :bruno) = aWorld();
      // A meeting that only Alice is invited to: with the token of Bruno, the
      // request is forbidden.
      world.load(
        ServerContent(
          meetings: [
            aMeeting(participants: [aParticipant()]),
          ],
          recordedVotes: const [],
        ),
      );
      await world.auth.signIn(alice);
      installed.conditions.delayMillis = 40;

      final inFlight = world.meetings.get(aMeetingId());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final signingIn = world.auth.signIn(bruno);
      final answer = await inFlight;
      await signingIn;
      installed.conditions.delayMillis = 0;

      expect(answer, isA<Ok<dynamic, dynamic>>());
      // From then on the token is Bruno's, and the same request is forbidden.
      expect(await world.meetings.get(aMeetingId()), equals(err(forbidden())));
    });

    test('signs in without a token: the request carries no Authorization '
        'header, and the password is in its body and nowhere else', () async {
      final (:world, :alice, bruno: _) = aWorld();

      await world.auth.signIn(alice);

      expect(installed.received, equals(['POST $testApiUrl${Routes.signIn}']));
      expect(
        installed.receivedHeader(0, HttpHeader.authorization.value),
        isNull,
      );
      expect(installed.received.single, isNot(contains(alice.password)));
    });
  });
}
