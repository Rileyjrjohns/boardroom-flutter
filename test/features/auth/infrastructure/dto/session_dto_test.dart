import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/domain/value_objects/credentials.dart';
import 'package:boardroom/features/auth/infrastructure/dto/session_dto.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';

final Map<String, Object?> _response = toSignInResponseWire(
  SignedIn(token: 'a-token', session: aSession()),
  3600,
).toJson();

Result<SignInResponseWire, WireFailure> _parse(Object? json) =>
    decodeWire(json, SignInResponseWire.fromJson);

bool _accepts(Map<String, Object?> change) =>
    _parse({..._response, ...change}) is Ok;

Map<String, Object?> get _user => _response['user']! as Map<String, Object?>;

void main() {
  group('the sign-in schemas', () {
    test('reads a response and ignores the fields it does not know', () {
      final parsed = unwrap(
        _parse({
          ..._response,
          'refreshToken': 'ignored',
          'user': {..._user, 'role': 'x'},
        }),
      );

      expect(parsed.accessToken, equals('a-token'));
      expect(parsed.toJson().containsKey('refreshToken'), isFalse);
    });

    for (final field in ['accessToken', 'tokenType', 'expiresIn', 'user']) {
      test('fails when $field is missing', () {
        final rest = {..._response}..remove(field);

        expect(_parse(rest), equals(err(WireFailure(field))));
      });
    }

    for (final field in ['id', 'fullName', 'email']) {
      test('fails when the user has no $field', () {
        final user = {..._user}..remove(field);

        expect(
          _parse({..._response, 'user': user}),
          equals(err(WireFailure('user.$field'))),
        );
      });
    }

    for (final (name, change) in <(String, Map<String, Object?>)>[
      ('an empty token', {'accessToken': ''}),
      ('a token that is a number', {'accessToken': 12}),
      ('a token type that is not Bearer', {'tokenType': 'Basic'}),
      ('a lifetime that is text', {'expiresIn': '3600'}),
      (
        'a lifetime beyond the maximum',
        {'expiresIn': maxSessionLifetimeSeconds + 1},
      ),
      ('a token with a space', {'accessToken': 'two words'}),
      ('a token with a line break', {'accessToken': 'abc\r\nX-Injected: 1'}),
      ('a token with a control character', {'accessToken': 'abc\u0007'}),
      (
        'a token with a character that is not ASCII',
        {'accessToken': 'jeton-é'},
      ),
      ('a token with a tab', {'accessToken': 'abc\tdef'}),
      ('a token that is too long', {'accessToken': 'a' * 4097}),
    ]) {
      test('fails for $name', () {
        expect(_accepts(change), isFalse);
      });
    }

    for (final (name, change) in <(String, Map<String, Object?>)>[
      ('the longest lifetime', {'expiresIn': maxSessionLifetimeSeconds}),
      ('a token of every visible character', {'accessToken': '!~09azAZ._-+/='}),
      ('the longest token', {'accessToken': 'a' * 4096}),
    ]) {
      test('accepts $name', () {
        expect(_accepts(change), isTrue);
      });
    }

    test('writes the request with the email and the password as '
        'typed, and reads it back', () {
      final wire = toSignInRequestWire(
        Credentials(email: anEmail(), password: ' pass word '),
      ).toJson();

      expect(
        wire,
        equals({'email': 'alice@example.com', 'password': ' pass word '}),
      );
      expect(switch (decodeWire(wire, SignInRequestWire.fromJson)) {
        Ok(:final value) => value.toJson(),
        Err() => null,
      }, equals(wire));
      expect(
        decodeWire({'email': 'a@b.cd'}, SignInRequestWire.fromJson),
        isA<Err<Object?, WireFailure>>(),
      );
    });
  });

  group('toSignedIn', () {
    test('builds the session on the clock of the device from the '
        'lifetime the server grants', () {
      final signedIn = toSignedIn(unwrap(_parse(_response)), now);

      expect(
        signedIn,
        equals(
          ok(
            SignedIn(
              token: 'a-token',
              session: createSession(user: aUser(), expiresAt: at(3600000)),
            ),
          ),
        ),
      );
    });

    test('does not copy any timestamp of the server', () {
      final wire = unwrap(
        _parse({..._response, 'expiresAt': '1999-01-01T00:00:00Z'}),
      );

      final signedIn = toSignedIn(wire, now);

      expect(unwrap(signedIn).session.expiresAt, equals(now + 3600000));
    });

    test('accepts a lifetime of zero: a session that is already over', () {
      final signedIn = toSignedIn(
        unwrap(_parse({..._response, 'expiresIn': 0})),
        now,
      );

      expect(unwrap(signedIn).session.expiresAt, equals(now));
    });

    for (final (name, change, field)
        in <(String, Map<String, Object?>, ValidationField)>[
          ('a blank id', {'id': ' '}, ValidationField.userId),
          (
            'an email that is not one',
            {'email': 'nobody'},
            ValidationField.email,
          ),
          ('a blank name', {'fullName': '  '}, ValidationField.fullName),
        ]) {
      test('refuses a user with $name through the factories of the domain', () {
        final wire = unwrap(
          _parse({
            ..._response,
            'user': {..._user, ...change},
          }),
        );

        expect(
          toSignedIn(wire, now),
          isA<Err<Object?, ValidationError>>().having(
            (result) => result.error.field,
            'field',
            field,
          ),
        );
      });
    }

    for (final (name, expiresIn) in <(String, num)>[
      ('a negative lifetime', -1),
      ('a lifetime that is not whole', 1.0000001),
    ]) {
      test('refuses $name', () {
        final wire = unwrap(_parse({..._response, 'expiresIn': expiresIn}));

        expect(toSignedIn(wire, now), isA<Err<Object?, ValidationError>>());
      });
    }

    test('refuses a session that would end beyond the range of an instant', () {
      final lastInstant = unwrap(parseInstant(8640000000000000));

      final signedIn = toSignedIn(unwrap(_parse(_response)), lastInstant);

      expect(signedIn, isA<Err<Object?, ValidationError>>());
    });
  });

  group('the sign-in wire classes, in Dart', () {
    test('never print the token nor the password', () {
      final response = unwrap(_parse(_response));
      final request = toSignInRequestWire(
        Credentials(email: anEmail(), password: 'a secret'),
      );
      final signedIn = unwrap(toSignedIn(response, now));

      expect('$response $request $signedIn', isNot(contains('a-token')));
      expect('$response $request $signedIn', isNot(contains('a secret')));
    });
  });
}
