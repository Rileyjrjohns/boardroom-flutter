import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/votes/application/use_cases/list_pending_votes.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/fakes/create_fakes.dart';
import 'votes_support.dart';

final PendingVote _first = aPendingVote(
  aVote(resolutionId: aResolutionId('r1')),
  at(-2000),
);
final PendingVote _second = aPendingVote(
  aVote(resolutionId: aResolutionId('r2')),
  at(-1000),
);
final RejectedVote _rejected = aRejectedVote(
  aVote(resolutionId: aResolutionId('r4')),
);
final PendingVote _others = aPendingVote(
  aVote(voterId: aUserId('user-2'), resolutionId: aResolutionId('r3')),
);
final RejectedVote _othersRejected = aRejectedVote(
  aVote(voterId: aUserId('user-2'), resolutionId: aResolutionId('r5')),
);

void main() {
  group('ListPendingVotes', () {
    test('lists the votes of the signed-in user, oldest first', () async {
      final fakes = createFakes();
      fakes.outbox.seed([_first, _second]);

      expect(
        await ListPendingVotes(fakes).execute(),
        equals(
          ok(
            OutboxContent(
              pending: [_first, _second],
              rejected: const [],
              unreadable: 0,
            ),
          ),
        ),
      );
    });

    test('tells the rejected votes from the pending ones', () async {
      final fakes = createFakes();
      fakes.outbox.seed([_first, _rejected, _second]);

      expect(
        await ListPendingVotes(fakes).execute(),
        equals(
          ok(
            OutboxContent(
              pending: [_first, _second],
              rejected: [_rejected],
              unreadable: 0,
            ),
          ),
        ),
      );
    });

    test(
      'never reads the votes of another user, pending or rejected',
      () async {
        final fakes = createFakes();
        fakes.outbox.seed([_first, _others, _othersRejected, _second]);

        expect(
          await ListPendingVotes(fakes).execute(),
          equals(
            ok(
              OutboxContent(
                pending: [_first, _second],
                rejected: const [],
                unreadable: 0,
              ),
            ),
          ),
        );
      },
    );

    test('lists nothing when the outbox is empty', () async {
      expect(
        await ListPendingVotes(createFakes()).execute(),
        equals(
          ok(const OutboxContent(pending: [], rejected: [], unreadable: 0)),
        ),
      );
    });

    test('says how many entries of the user cannot be read as a vote, and '
        'lists the others', () async {
      final fakes = createFakes();
      fakes.outbox.seed([_first]);
      fakes.outbox.seedUnreadable(aUserId(), 'k1');
      fakes.outbox.seedUnreadable(aUserId(), 'k2');
      fakes.outbox.seedUnreadable(aUserId('user-2'), 'k3');

      expect(
        await ListPendingVotes(fakes).execute(),
        equals(
          ok(
            OutboxContent(pending: [_first], rejected: const [], unreadable: 2),
          ),
        ),
      );
    });

    test(
      'does not delete what it cannot read: asking again says the same',
      () async {
        final fakes = createFakes();
        fakes.outbox.seedUnreadable(aUserId(), 'k1');
        final useCase = ListPendingVotes(fakes);

        await useCase.execute();
        final again = await useCase.execute();

        expect(valueOf(again)?.unreadable, equals(1));
        expect(fakes.outbox.unreadableSnapshot(), hasLength(1));
      },
    );

    test('requires a valid session', () async {
      final fakes = createFakes();
      fakes.auth.session = null;
      expect(
        await ListPendingVotes(fakes).execute(),
        equals(err(notAuthenticated())),
      );

      fakes.auth.session = aSession(expiresAt: now);
      expect(
        await ListPendingVotes(fakes).execute(),
        equals(err(sessionExpired())),
      );
    });

    test(
      'never returns the entries of a user once somebody else is signed in',
      () async {
        final fakes = createFakes();
        fakes.outbox.seed([_first, _rejected]);
        fakes.outbox.seedUnreadable(aUserId(), 'k1');
        fakes.outbox.onRequest = () {
          fakes.auth.session = aSession(user: aUser(id: aUserId('user-2')));
        };

        expect(
          await ListPendingVotes(fakes).execute(),
          equals(err(sessionChanged())),
        );
      },
    );

    test(
      'never returns the entries of a user once the app is locked',
      () async {
        final fakes = createFakes();
        fakes.outbox.seed([_first]);
        fakes.outbox.onRequest = fakes.appLock.lock;

        expect(
          await ListPendingVotes(fakes).execute(),
          equals(err(appLocked())),
        );
      },
    );

    test('returns the storage error when the outbox cannot be read', () async {
      final fakes = createFakes();
      fakes.outbox.listFailure = storageReadFailed();

      expect(
        await ListPendingVotes(fakes).execute(),
        equals(err(storageReadFailed())),
      );
    });
  });
}
