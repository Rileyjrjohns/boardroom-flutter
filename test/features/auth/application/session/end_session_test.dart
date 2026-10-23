import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/auth/application/session/end_session.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/fakes/create_fakes.dart';
import '../../../../support/fakes/fake_monitoring.dart';

final UserId _alice = aUserId();
final UserId _bruno = aUserId('user-2');

Future<void> _fill(Fakes fakes) async {
  await fakes.meetingCache.saveMeeting(_alice, aMeeting(), now);
  await fakes.documentCache.save(
    _alice,
    ViewableDocument(document: aDocument(), location: aDocumentLocation()),
    now,
  );
}

void main() {
  group('closeSession', () {
    test(
      'locks the app, empties both caches and forgets the session',
      () async {
        final fakes = createFakes();
        await _fill(fakes);

        final closed = await closeSession(fakes);

        expect(isOk(closed), isTrue);
        expect(fakes.appLock.isLocked(), isTrue);
        expect(fakes.meetingCache.isEmpty(), isTrue);
        expect(fakes.documentCache.isEmpty(), isTrue);
        expect(fakes.auth.session, isNull);
      },
    );

    test(
      'gives the failure of the storage that cannot forget the session',
      () async {
        final fakes = createFakes();
        fakes.auth.signOutFailure = storageWriteFailed();

        expect(await closeSession(fakes), equals(err(storageWriteFailed())));
        expect(fakes.appLock.isLocked(), isTrue);
      },
    );
  });

  group('endRefusedSession', () {
    test(
      'ends the session of the user whose token the server refused',
      () async {
        final fakes = createFakes();
        await _fill(fakes);

        await endRefusedSession(fakes, _alice);

        expect(fakes.auth.signOutCalls, equals(1));
        expect(fakes.auth.session, isNull);
        expect(fakes.appLock.isLocked(), isTrue);
        expect(fakes.meetingCache.isEmpty(), isTrue);
        expect(fakes.documentCache.isEmpty(), isTrue);
        expect(fakes.monitoring.errors, isEmpty);
      },
    );

    test('leaves alone the session of somebody else, who signed in while the '
        'request was on its way', () async {
      final fakes = createFakes();
      fakes.auth.session = aSession(user: aUser(id: _bruno));
      await _fill(fakes);

      await endRefusedSession(fakes, _alice);

      expect(fakes.auth.signOutCalls, equals(0));
      expect(fakes.auth.session, isNotNull);
      expect(fakes.appLock.isLocked(), isFalse);
      expect(fakes.meetingCache.isEmpty(), isFalse);
    });

    test('does nothing when nobody is signed in any more', () async {
      final fakes = createFakes();
      fakes.auth.session = null;

      await endRefusedSession(fakes, _alice);

      expect(fakes.auth.signOutCalls, equals(0));
    });

    test('ends the session even when it cannot be read: it is the one the '
        'server refused, as far as anyone can tell', () async {
      final fakes = createFakes();
      fakes.auth.readFailure = storageReadFailed();

      await endRefusedSession(fakes, _alice);

      expect(fakes.auth.signOutCalls, equals(1));
      expect(fakes.appLock.isLocked(), isTrue);
    });

    test(
      'captures a session that cannot be forgotten, and does not fail',
      () async {
        final fakes = createFakes();
        fakes.auth.signOutFailure = storageWriteFailed('keychain locked');

        await expectLater(endRefusedSession(fakes, _alice), completion(isNull));

        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.signOutFailed,
              error: storageWriteFailed('keychain locked'),
              attributes: {LogAttribute.userId: _alice},
            ),
          ]),
        );
        expect(fakes.appLock.isLocked(), isTrue);
      },
    );
  });
}
