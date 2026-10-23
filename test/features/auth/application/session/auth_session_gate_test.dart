import 'package:boardroom/core/application/ports/types/session_refusal.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/auth/application/session/auth_session_gate.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/fakes/create_fakes.dart';

// The gate gives `loadWithCacheFallback`, which lives in core and knows no
// feature, the answers of the session guards of auth in the terms of core (see
// docs/architecture.md).

final UserId _alice = aUserId();
final UserId _bruno = aUserId('user-2');

({Fakes fakes, AuthSessionGate gate}) _aGate() {
  final fakes = createFakes();
  return (fakes: fakes, gate: AuthSessionGate(fakes));
}

void main() {
  group('AuthSessionGate', () {
    group('requireSameUser', () {
      test('gives the id of the user who is signed in, when it is the one '
          'expected and the app is open', () async {
        final (:gate, fakes: _) = _aGate();

        final answer = await gate.requireSameUser(aUserId());

        expect(answer, equals(ok(aUserId())));
      });

      test('refuses with sessionChanged when somebody else is signed in, and '
          'the session is not kept', () async {
        final (:gate, fakes: _) = _aGate();

        final answer = await gate.requireSameUser(_bruno);

        expect(
          answer,
          equals(
            err(SessionRefusal(error: sessionChanged(), sessionKept: false)),
          ),
        );
      });

      test('refuses with notAuthenticated when nobody is signed in', () async {
        final (:fakes, :gate) = _aGate();
        fakes.auth.session = null;

        final answer = await gate.requireSameUser(_alice);

        expect(
          answer,
          equals(
            err(SessionRefusal(error: notAuthenticated(), sessionKept: false)),
          ),
        );
      });

      test('refuses with sessionExpired when the session has expired, and '
          'empties what it left', () async {
        final (:fakes, :gate) = _aGate();
        fakes.auth.session = aSession(expiresAt: at(-1));
        await fakes.meetingCache.saveMeeting(aUserId(), aMeeting(), now);

        final answer = await gate.requireSameUser(aUserId());

        expect(
          answer,
          equals(
            err(SessionRefusal(error: sessionExpired(), sessionKept: false)),
          ),
        );
        expect(fakes.meetingCache.isEmpty(), isTrue);
      });

      test('refuses with appLocked when the app is locked, and says the '
          'session is kept: the user comes back', () async {
        final (:fakes, :gate) = _aGate();
        fakes.appLock.lock();

        final answer = await gate.requireSameUser(aUserId());

        expect(
          answer,
          equals(err(SessionRefusal(error: appLocked(), sessionKept: true))),
        );
      });

      test('refuses with the failure of the storage that cannot read the '
          'session, which is not kept', () async {
        final (:fakes, :gate) = _aGate();
        fakes.auth.readFailure = storageReadFailed();

        final answer = await gate.requireSameUser(aUserId());

        expect(
          answer,
          equals(
            err(SessionRefusal(error: storageReadFailed(), sessionKept: false)),
          ),
        );
      });
    });

    group('endRefusedSession', () {
      test('ends the session of the user whose token the server refused: '
          'locks, empties, forgets', () async {
        final (:fakes, :gate) = _aGate();
        await fakes.meetingCache.saveMeeting(_alice, aMeeting(), now);

        await gate.endRefusedSession(aUserId());

        expect(fakes.appLock.isLocked(), isTrue);
        expect(fakes.meetingCache.isEmpty(), isTrue);
        expect(fakes.auth.session, isNull);
      });

      test('leaves alone the session of somebody else, who signed in while '
          'the request was on its way', () async {
        final (:fakes, :gate) = _aGate();
        fakes.auth.session = aSession(user: aUser(id: _bruno));

        await gate.endRefusedSession(_alice);

        expect(fakes.auth.session, isNotNull);
        expect(fakes.appLock.isLocked(), isFalse);
      });
    });

    group('purgeSessionData', () {
      test('empties what the session left on the device, for every owner, '
          'and keeps the session', () async {
        final (:fakes, :gate) = _aGate();
        await fakes.meetingCache.saveMeeting(_alice, aMeeting(), now);
        await fakes.documentCache.save(
          _bruno,
          ViewableDocument(
            document: aDocument(),
            location: aDocumentLocation(),
          ),
          now,
        );

        await gate.purgeSessionData();

        expect(fakes.meetingCache.isEmpty(), isTrue);
        expect(fakes.documentCache.isEmpty(), isTrue);
        expect(fakes.auth.session, isNotNull);
      });

      test('captures a purge that fails and does not throw', () async {
        final (:fakes, :gate) = _aGate();
        fakes.meetingCache.purgeFailure = storageWriteFailed();

        await gate.purgeSessionData();

        expect(fakes.monitoring.errors, hasLength(1));
      });
    });
  });
}
