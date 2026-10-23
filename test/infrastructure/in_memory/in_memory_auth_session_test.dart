import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/policies/session_expiry.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/credentials.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:test/test.dart';

import '../../application/support/contracts/auth_session_contract.dart';
import '../../domain/support/builders.dart';
import '../support/test_server.dart';

/// The latest instant there is: any session opened then would end after it.
final Instant _lastInstant = unwrap(parseInstant(8640000000000000));

const TestServerOptions _signedOut = TestServerOptions(signedIn: false);

void main() {
  describeAuthSessionContract('InMemoryAuthSession', () {
    final server = createTestServer(_signedOut);
    final [first, second] = server.accounts;
    return AuthSessionHarness(
      auth: server.auth,
      accounts: (
        AuthSessionAccount(credentials: credentialsOf(first), user: first.user),
        AuthSessionAccount(
          credentials: credentialsOf(second),
          user: second.user,
        ),
      ),
      now: server.clock.now,
      advanceClock: server.clock.advance,
      setOnline: server.network.setOnline,
    );
  });

  group('InMemoryAuthSession', () {
    test(
      'ends a session one lifetime after the sign-in, on the clock it is given',
      () async {
        final server = createTestServer(_signedOut);
        final alice = server.accounts.first;

        final session = await server.auth.signIn(
          Credentials(email: alice.user.email, password: testPassword),
        );

        expect(
          session,
          equals(ok(aSession(user: alice.user, expiresAt: at(millisPerHour)))),
        );
      },
    );

    test('counts the lifetime from the instant of each sign-in', () async {
      final server = createTestServer(_signedOut);
      final alice = server.accounts.first;
      server.clock.advance(5000);

      await server.auth.signIn(
        Credentials(email: alice.user.email, password: testPassword),
      );
      final current = unwrap(await server.auth.current());

      expect(current?.expiresAt, equals(at(5000 + millisPerHour)));
    });

    test('expires the session it opened when its lifetime is over', () {
      final server = createTestServer(_signedOut);
      final alice = server.accounts.first;
      final opened = server.auth.openSessionFor(alice.user);
      server.clock.advance(millisPerHour - 1);

      final session = unwrap(opened);
      expect(isSessionExpired(session, server.clock.now()), isFalse);
      server.clock.advance(1);
      expect(isSessionExpired(session, server.clock.now()), isTrue);
    });

    test(
      'opens a session for a user without credentials, and signs that user in',
      () async {
        final server = createTestServer(_signedOut);
        final alice = server.accounts.first;

        final opened = server.auth.openSessionFor(alice.user);

        expect(
          opened,
          equals(ok(aSession(user: alice.user, expiresAt: at(millisPerHour)))),
        );
        expect(await server.auth.current(), equals(opened));
      },
    );

    test('refuses to open a session that would end beyond the range of an '
        'instant', () {
      final server = createTestServer(_signedOut);
      server.clock.set(_lastInstant);

      expect(isErr(server.auth.openSessionFor(aUser())), isTrue);
    });

    test('answers unexpected, not a thrown error, when it cannot compute the '
        'expiry of a sign-in', () async {
      final server = createTestServer(_signedOut);
      final alice = server.accounts.first;
      server.clock.set(_lastInstant);

      final result = await server.auth.signIn(
        Credentials(email: alice.user.email, password: testPassword),
      );

      expect(result, equals(err(unexpected())));
    });

    test(
      'compares the email in the form the domain normalised it to',
      () async {
        final server = createTestServer(_signedOut);
        final bruno = server.accounts[1];

        expect(
          await server.auth.signIn(
            Credentials(email: bruno.user.email, password: testPassword),
          ),
          equals(ok(aSession(user: bruno.user, expiresAt: at(millisPerHour)))),
        );
        expect(
          await server.auth.signIn(
            Credentials(email: bruno.user.email, password: 'wrong'),
          ),
          equals(err(invalidCredentials())),
        );
      },
    );
  });
}
