import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/votes/application/use_cases/acknowledge_rejected_vote.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/fakes/create_fakes.dart';

final ResolutionId _resolutionId = aResolutionId();
final RejectedVote _rejected = aRejectedVote();

void main() {
  group('AcknowledgeRejectedVote', () {
    test('deletes the rejected vote of the user on the resolution', () async {
      final fakes = createFakes();
      fakes.outbox.seed([_rejected]);

      expect(
        await AcknowledgeRejectedVote(fakes)
            .execute(resolutionId: _resolutionId),
        equals(ok<void>(null)),
      );
      expect(fakes.outbox.snapshot(), equals(<OutboxVote>[]));
    });

    test('leaves the other votes alone', () async {
      final fakes = createFakes();
      final other = aRejectedVote(aVote(resolutionId: aResolutionId('r2')));
      final pending = aPendingVote(aVote(resolutionId: aResolutionId('r3')));
      fakes.outbox.seed([other, _rejected, pending]);

      await AcknowledgeRejectedVote(fakes).execute(resolutionId: _resolutionId);

      expect(fakes.outbox.snapshot(), equals([other, pending]));
    });

    test(
      'does not delete a vote that is still pending: it leaves the outbox by '
      'being sent',
      () async {
        final fakes = createFakes();
        final pending = aPendingVote();
        fakes.outbox.seed([pending]);

        expect(
          await AcknowledgeRejectedVote(fakes)
              .execute(resolutionId: _resolutionId),
          equals(err(voteNotRejected())),
        );
        expect(fakes.outbox.snapshot(), equals([pending]));
      },
    );

    test(
      'is harmless when there is nothing to acknowledge, as on a double tap',
      () async {
        final fakes = createFakes();
        fakes.outbox.seed([_rejected]);
        final useCase = AcknowledgeRejectedVote(fakes);

        await useCase.execute(resolutionId: _resolutionId);

        expect(
          await useCase.execute(resolutionId: _resolutionId),
          equals(ok<void>(null)),
        );
      },
    );

    test('cannot delete the rejected vote of another user', () async {
      final fakes = createFakes();
      final others = aRejectedVote(aVote(voterId: aUserId('user-2')));
      fakes.outbox.seed([others]);

      expect(
        await AcknowledgeRejectedVote(fakes)
            .execute(resolutionId: _resolutionId),
        equals(ok<void>(null)),
      );
      expect(fakes.outbox.snapshot(), equals([others]));
    });

    test('requires a valid session', () async {
      final fakes = createFakes();
      fakes.outbox.seed([_rejected]);
      final useCase = AcknowledgeRejectedVote(fakes);

      fakes.auth.session = null;
      expect(
        await useCase.execute(resolutionId: _resolutionId),
        equals(err(notAuthenticated())),
      );

      fakes.auth.session = aSession(expiresAt: now);
      expect(
        await useCase.execute(resolutionId: _resolutionId),
        equals(err(sessionExpired())),
      );
      expect(fakes.outbox.snapshot(), equals([_rejected]));
    });

    test('deletes nothing once somebody else is signed in', () async {
      final fakes = createFakes();
      fakes.outbox.seed([_rejected]);
      fakes.outbox.onRequest = () {
        fakes.auth.session = aSession(user: aUser(id: aUserId('user-2')));
      };

      expect(
        await AcknowledgeRejectedVote(fakes)
            .execute(resolutionId: _resolutionId),
        equals(err(sessionChanged())),
      );
      expect(fakes.outbox.snapshot(), equals([_rejected]));
    });

    test('deletes nothing once the app is locked', () async {
      final fakes = createFakes();
      fakes.outbox.seed([_rejected]);
      fakes.outbox.onRequest = fakes.appLock.lock;

      expect(
        await AcknowledgeRejectedVote(fakes)
            .execute(resolutionId: _resolutionId),
        equals(err(appLocked())),
      );
      expect(fakes.outbox.snapshot(), equals([_rejected]));
    });

    test('returns the storage errors of the outbox', () async {
      final fakes = createFakes();
      fakes.outbox.seed([_rejected]);
      final useCase = AcknowledgeRejectedVote(fakes);

      fakes.outbox.findFailure = storageReadFailed();
      expect(
        await useCase.execute(resolutionId: _resolutionId),
        equals(err(storageReadFailed())),
      );

      fakes.outbox.findFailure = null;
      fakes.outbox.removeFailure = storageWriteFailed();
      expect(
        await useCase.execute(resolutionId: _resolutionId),
        equals(err(storageWriteFailed())),
      );
      expect(fakes.outbox.snapshot(), equals([_rejected]));
    });
  });
}
