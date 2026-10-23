import 'dart:async';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/auth/application/ports/auth_session.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/domain/entities/user.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/policies/session_expiry.dart';
import 'package:boardroom/features/auth/domain/value_objects/credentials.dart';
import 'package:boardroom/features/auth/domain/value_objects/email_address.dart';
import 'package:test/test.dart';

import '../builders/builders.dart';
import 'support.dart';

/// An account the adapter accepts.
final class AuthSessionAccount {
  /// Creates an account.
  const new({required this.credentials, required this.user});

  /// What signs in to the account.
  final Credentials credentials;

  /// The user the adapter opens a session for when these credentials are
  /// accepted.
  final User user;
}

/// What the suite needs besides the port.
final class AuthSessionHarness {
  /// Creates a harness.
  const new({
    required this.auth,
    required this.accounts,
    required this.now,
    required this.advanceClock,
    required this.setOnline,
  });

  /// The adapter under test.
  final AuthSession auth;

  /// Two accounts the adapter accepts, of two different users. Nobody is signed
  /// in at first.
  final (AuthSessionAccount, AuthSessionAccount) accounts;

  /// The instant the adapter reads from its clock.
  final Instant Function() now;

  /// Moves the clock of the adapter forward.
  final void Function(int millis) advanceClock;

  /// Cuts and restores the connection a sign-in needs.
  final void Function({required bool online}) setOnline;
}

/// Makes a harness, now or later.
typedef AuthSessionFactory = FutureOr<AuthSessionHarness> Function();

final EmailAddress _unknownEmail = anEmail('nobody@example.com');

/// The contract of `AuthSession`, as a suite any implementation runs:
/// credentials are checked, the session is remembered and returned as stored
/// (expired or not), signing out forgets it and always succeeds, and a session
/// ends at an instant computed on the clock of the adapter.
void describeAuthSessionContract(
  String name,
  AuthSessionFactory createHarness,
) {
  group('$name honours the AuthSession contract', () {
    late AuthSessionHarness harness;
    late AuthSession auth;
    late AuthSessionAccount alice;
    late AuthSessionAccount bruno;

    setUp(() async {
      harness = await createHarness();
      auth = harness.auth;
      (alice, bruno) = harness.accounts;
    });

    test(
      'has nobody signed in at first, which is a success and not an error',
      () async {
        expect(await auth.current(), equals(ok<Session?>(null)));
      },
    );

    test('signs in an account and returns the session of its user, '
        'which ends in the future', () async {
      final session = valueOf(await auth.signIn(alice.credentials));

      expect(session.user, equals(alice.user));
      expect(session.expiresAt, greaterThan(harness.now()));
      expect(isSessionExpired(session, harness.now()), isFalse);
    });

    test('remembers the session it opened', () async {
      final session = valueOf(await auth.signIn(alice.credentials));

      expect(await auth.current(), equals(ok(session)));
    });

    test('returns the session as stored even when its expiry has passed: '
        'deciding that is not its job', () async {
      final session = valueOf(await auth.signIn(alice.credentials));

      harness.advanceClock(session.expiresAt - harness.now() + 1);

      expect(isSessionExpired(session, harness.now()), isTrue);
      expect(await auth.current(), equals(ok(session)));
    });

    final tampers = <(String, Credentials Function(Credentials))>[
      ('a wrong password', (c) => c.copyWith(password: '${c.password}x')),
      (
        'a password in another case',
        (c) => c.copyWith(password: c.password.toUpperCase()),
      ),
      (
        'a password that was trimmed',
        (c) => c.copyWith(password: '${trimText(c.password)} '),
      ),
      ('an email nobody registered', (c) => c.copyWith(email: _unknownEmail)),
    ];
    for (final (tamperName, tamper) in tampers) {
      test(
        'refuses $tamperName with invalidCredentials, and signs nobody in',
        () async {
          expect(
            await auth.signIn(tamper(alice.credentials)),
            equals(err(invalidCredentials())),
          );

          expect(await auth.current(), equals(ok<Session?>(null)));
        },
      );
    }

    test('keeps the current session when a later sign-in is refused', () async {
      final session = valueOf(await auth.signIn(alice.credentials));

      await auth.signIn(
        bruno.credentials.copyWith(password: '${bruno.credentials.password}x'),
      );

      expect(await auth.current(), equals(ok(session)));
    });

    test('replaces the session when another user signs in', () async {
      await auth.signIn(alice.credentials);
      final second = valueOf(await auth.signIn(bruno.credentials));

      expect(second.user, equals(bruno.user));
      expect(await auth.current(), equals(ok(second)));
    });

    test('forgets the session on sign-out, '
        'and succeeds when nobody was signed in', () async {
      await auth.signIn(alice.credentials);

      expect(await auth.signOut(), equals(ok<void>(null)));
      expect(await auth.current(), equals(ok<Session?>(null)));
      expect(await auth.signOut(), equals(ok<void>(null)));
    });

    test('answers networkUnavailable to a sign-in without a connection, '
        'signs nobody in, and recovers', () async {
      harness.setOnline(online: false);

      expect(
        await auth.signIn(alice.credentials),
        equals(err(networkUnavailable())),
      );
      expect(await auth.current(), equals(ok<Session?>(null)));

      harness.setOnline(online: true);
      expect(isOk(await auth.signIn(alice.credentials)), isTrue);
    });
  });
}
