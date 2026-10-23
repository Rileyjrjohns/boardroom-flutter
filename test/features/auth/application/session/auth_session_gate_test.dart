import 'package:boardroom/core/application/ports/types/session_refusal.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/session/app_lock.dart';
import 'package:boardroom/features/auth/application/session/auth_session_gate.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/fakes/create_fakes.dart';

// Dart only: the gate gives `loadWithCacheFallback`, which lives in core and
// knows no feature, the answers of the session guards of auth in the terms of
// core (see docs/architecture.md).

Future<void> _fill(Fakes fakes) async {
  await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);
  await fakes.documentCache.save(
    aUserId(),
    ViewableDocument(document: aDocument(), location: aDocumentLocation()),
    now,
  );
}

void main() {
  group('AuthSessionGate', () {
    group('requireSameUser', () {
      test('answers with the user when it is the one signed in', () async {
        final gate = AuthSessionGate(createFakes());

        expect(await gate.requireSameUser(aUserId()), equals(ok(aUserId())));
      });

      test('refuses with sessionChanged when somebody else is signed in, and '
          'the session is not kept', () async {
        final gate = AuthSessionGate(createFakes());

        expect(
          await gate.requireSameUser(aUserId('user-2')),
          equals(
            err(SessionRefusal(error: sessionChanged(), sessionKept: false)),
          ),
        );
      });

      test('refuses with notAuthenticated when nobody is signed in', () async {
        final fakes = createFakes();
        fakes.auth.session = null;

        expect(
          await AuthSessionGate(fakes).requireSameUser(aUserId()),
          equals(
            err(SessionRefusal(error: notAuthenticated(), sessionKept: false)),
          ),
        );
      });

      test('refuses with sessionExpired and empties the caches when the '
          'session has expired', () async {
        final fakes = createFakes();
        await _fill(fakes);
        fakes.clock.advance(millisPerHour);

        expect(
          await AuthSessionGate(fakes).requireSameUser(aUserId()),
          equals(
            err(SessionRefusal(error: sessionExpired(), sessionKept: false)),
          ),
        );
        expect(fakes.meetingCache.isEmpty(), isTrue);
        expect(fakes.documentCache.isEmpty(), isTrue);
      });

      test('refuses with appLocked and says the session is kept, so that the '
          'caller leaves the caches of the user alone', () async {
        final fakes = createFakes().copyWith(appLock: AppLock());

        expect(
          await AuthSessionGate(fakes).requireSameUser(aUserId()),
          equals(err(SessionRefusal(error: appLocked(), sessionKept: true))),
        );
      });

      test('refuses with the storage error when the session cannot be read, '
          'and the session is not kept', () async {
        final fakes = createFakes();
        fakes.auth.readFailure = storageReadFailed();

        expect(
          await AuthSessionGate(fakes).requireSameUser(aUserId()),
          equals(
            err(SessionRefusal(error: storageReadFailed(), sessionKept: false)),
          ),
        );
      });
    });

    group('endRefusedSession', () {
      test('ends the session of the user: locked app, empty caches, no '
          'session', () async {
        final fakes = createFakes();
        await _fill(fakes);

        await AuthSessionGate(fakes).endRefusedSession(aUserId());

        expect(fakes.appLock.isLocked(), isTrue);
        expect(fakes.meetingCache.isEmpty(), isTrue);
        expect(fakes.documentCache.isEmpty(), isTrue);
        expect(fakes.auth.session, isNull);
      });

      test(
        'leaves the session alone when it is another one that is open',
        () async {
          final fakes = createFakes();
          await _fill(fakes);

          await AuthSessionGate(fakes).endRefusedSession(aUserId('user-2'));

          expect(fakes.appLock.isLocked(), isFalse);
          expect(fakes.meetingCache.isEmpty(), isFalse);
          expect(fakes.auth.session, equals(aSession()));
        },
      );
    });

    group('purgeSessionData', () {
      test('empties the caches of every owner and keeps the session', () async {
        final fakes = createFakes();
        await _fill(fakes);

        await AuthSessionGate(fakes).purgeSessionData();

        expect(fakes.meetingCache.isEmpty(), isTrue);
        expect(fakes.documentCache.isEmpty(), isTrue);
        expect(fakes.auth.session, equals(aSession()));
      });

      test('captures a purge that fails and does not throw', () async {
        final fakes = createFakes();
        fakes.meetingCache.purgeFailure = storageWriteFailed();

        await AuthSessionGate(fakes).purgeSessionData();

        expect(fakes.monitoring.errors, hasLength(1));
      });
    });
  });
}
