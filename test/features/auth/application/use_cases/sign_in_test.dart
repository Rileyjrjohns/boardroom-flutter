import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/auth_session.dart';
import 'package:boardroom/features/auth/application/ports/session_data_purger.dart';
import 'package:boardroom/features/auth/application/session/app_lock.dart';
import 'package:boardroom/features/auth/application/session/end_session.dart';
import 'package:boardroom/features/auth/application/use_cases/sign_in.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/value_objects/credentials.dart';
import 'package:boardroom/features/documents/application/document_cache_purger.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:boardroom/features/meetings/application/meeting_cache_purger.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/fakes/create_fakes.dart';
import '../../../../support/fakes/fake_auth_session.dart';
import '../../../../support/fakes/fake_meeting_cache.dart';

/// A cache of meetings that tells when it is emptied, so that a test can look
/// at the lock at that moment: the Dart counterpart of replacing `purge` of the
/// fake.
final class _SpyMeetingCache extends FakeMeetingCache {
  new(this._onPurge);

  final void Function() _onPurge;

  @override
  Future<Result<void, StorageWriteFailedError>> purge() {
    _onPurge();
    return super.purge();
  }
}

/// The fakes, with another cache of meetings: the Dart counterpart of
/// `{ ...fakes, meetingCache }`.
final class _DepsWithCache implements EndSessionDeps {
  const new(this._fakes, this._meetingCache);

  final Fakes _fakes;

  final FakeMeetingCache _meetingCache;

  @override
  AuthSession get auth => _fakes.auth;

  @override
  AppLock get appLock => _fakes.appLock;

  @override
  List<SessionDataPurger> get sessionDataPurgers => [
    MeetingCachePurger(_meetingCache),
    DocumentCachePurger(_fakes.documentCache),
  ];

  @override
  Monitoring get monitoring => _fakes.monitoring;
}

const String _email = 'alice@example.com';

void main() {
  group('SignIn', () {
    test('signs the user in with validated credentials and returns the '
        'session', () async {
      final fakes = createFakes();
      fakes.auth.session = null;

      final result = await SignIn(fakes)
          .execute(email: '  Alice@Example.com ', password: defaultPassword);

      expect(result, equals(ok(aSession())));
      expect(
        fakes.auth.signInCalls,
        equals([
          Credentials(
            // The default of the builder, written out as the scenario does.
            // ignore: avoid_redundant_argument_values
            email: anEmail('alice@example.com'),
            password: defaultPassword,
          ),
        ]),
      );
      expect(fakes.auth.session, equals(aSession()));
    });

    test('hands the password to the port exactly as typed: the spaces around '
        'it count', () async {
      final fakes = createFakes();
      final bruno = aSession(
        user: aUser(id: aUserId('user-2'), email: anEmail('bruno@example.com')),
      );
      fakes.auth.registerAccount(
        anEmail('bruno@example.com'),
        '  p4ss word  ',
        bruno,
      );

      final result = await SignIn(fakes)
          .execute(email: 'bruno@example.com', password: '  p4ss word  ');

      expect(result, equals(ok(bruno)));
      expect(
        fakes.auth.signInCalls,
        equals([
          Credentials(
            email: anEmail('bruno@example.com'),
            password: '  p4ss word  ',
          ),
        ]),
      );
    });

    for (final (name, password) in [
      ('a password with its spaces cut', 'p4ss word'),
      ('a password in another case', '  P4SS WORD  '),
    ]) {
      test('does not sign in with $name', () async {
        final fakes = createFakes();
        fakes.auth.registerAccount(
          anEmail('bruno@example.com'),
          '  p4ss word  ',
          aSession(),
        );
        fakes.auth.session = null;

        expect(
          await SignIn(fakes)
              .execute(email: 'bruno@example.com', password: password),
          equals(err(invalidCredentials())),
        );
      });
    }

    for (final (name, email, password, field, rule) in [
      (
        'a malformed email',
        'alice',
        'secret',
        ValidationField.email,
        ValidationRule.invalidFormat,
      ),
      (
        'a blank email',
        ' ',
        'secret',
        ValidationField.email,
        ValidationRule.required,
      ),
      (
        'an empty password',
        _email,
        '',
        ValidationField.password,
        ValidationRule.required,
      ),
    ]) {
      test('rejects $name without calling the server', () async {
        final fakes = createFakes();

        expect(
          await SignIn(fakes).execute(email: email, password: password),
          equals(err(validationError(field, rule))),
        );
        expect(fakes.auth.signInCalls, equals(<Credentials>[]));
      });
    }

    test('returns the refusal of the server for a wrong password', () async {
      final fakes = createFakes();
      fakes.auth.session = null;

      expect(
        await SignIn(fakes).execute(email: _email, password: 'wrong'),
        equals(err(invalidCredentials())),
      );
      expect(fakes.auth.session, isNull);
    });

    test('returns a network failure', () async {
      final fakes = createFakes();
      fakes.auth.signInFailure = networkUnavailable();

      expect(
        await SignIn(fakes).execute(email: _email, password: defaultPassword),
        equals(err(networkUnavailable())),
      );
    });

    group('the caches and the lock', () {
      Future<void> fill(Fakes fakes) async {
        await fakes.meetingCache.saveMeeting(
          aUserId('user-2'),
          aMeeting(),
          now,
        );
        await fakes.documentCache.save(
          aUserId('user-2'),
          ViewableDocument(
            document: aDocument(),
            location: aDocumentLocation(),
          ),
          now,
        );
      }

      test('empties both caches once the credentials are accepted: the '
          'previous user leaves nothing behind', () async {
        final fakes = createFakes();
        await fill(fakes);

        await SignIn(fakes).execute(email: _email, password: defaultPassword);

        expect(fakes.meetingCache.isEmpty(), isTrue);
        expect(fakes.documentCache.isEmpty(), isTrue);
      });

      test(
        'empties them for every owner, the signed-in user included',
        () async {
          final fakes = createFakes();
          await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);

          await SignIn(fakes).execute(email: _email, password: defaultPassword);

          expect(fakes.meetingCache.isEmpty(), isTrue);
        },
      );

      for (final (name, email, password) in [
        ('wrong credentials', _email, 'wrong'),
        ('a badly formed email', 'alice', defaultPassword),
      ]) {
        test('leaves the caches alone on $name', () async {
          final fakes = createFakes();
          await fill(fakes);

          await SignIn(fakes).execute(email: email, password: password);

          expect(fakes.meetingCache.isEmpty(), isFalse);
          expect(fakes.documentCache.isEmpty(), isFalse);
        });
      }

      test(
        'leaves the caches alone when the server cannot be reached',
        () async {
          final fakes = createFakes();
          await fill(fakes);
          fakes.auth.signInFailure = networkUnavailable();

          await SignIn(fakes).execute(email: _email, password: defaultPassword);

          expect(fakes.meetingCache.isEmpty(), isFalse);
        },
      );

      test('signs in anyway, and captures the failure, when a cache cannot be '
          'emptied', () async {
        final fakes = createFakes();
        await fill(fakes);
        fakes.documentCache.purgeFailure = storageWriteFailed();

        final result = await SignIn(fakes)
            .execute(email: _email, password: defaultPassword);

        expect(isOk(result), isTrue);
        expect(
          fakes.monitoring.capturedEvents(),
          equals([MonitoringEvent.cachePurgeFailed]),
        );
      });

      test('leaves the app unlocked after a sign-in: the credentials just '
          'typed are the proof of presence', () async {
        final fakes = createFakes();
        fakes.appLock.lock();

        await SignIn(fakes).execute(email: _email, password: defaultPassword);

        expect(fakes.appLock.isLocked(), isFalse);
      });

      test('keeps the app locked when the sign-in is refused', () async {
        final fakes = createFakes();
        fakes.appLock.lock();

        await SignIn(fakes).execute(email: _email, password: 'wrong');

        expect(fakes.appLock.isLocked(), isTrue);
      });

      test('is locked while the caches are emptied, and opened only '
          'afterwards', () async {
        final fakes = createFakes();
        final seen = <bool>[];
        final spy = _SpyMeetingCache(() => seen.add(fakes.appLock.isLocked()));

        await SignIn(_DepsWithCache(fakes, spy))
            .execute(email: _email, password: defaultPassword);

        expect(seen, equals([true]));
        expect(fakes.appLock.isLocked(), isFalse);
      });
    });
  });
}
