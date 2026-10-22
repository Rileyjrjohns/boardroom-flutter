import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:test/test.dart';

import '../support/builders.dart';
import '../support/names.dart';

void main() {
  group('createPendingVote', () {
    test('starts pending, with no attempt', () {
      final pending = createPendingVote(aVote(), now);

      expect(pending.status, equals(OutboxStatus.pending));
      expect(
        pending,
        equals(PendingVote(vote: aVote(), enqueuedAt: now, attempts: 0)),
      );
    });
  });

  group('recordAttempt', () {
    test('counts one more attempt and leaves the original untouched', () {
      final pending = createPendingVote(aVote(), now);

      final retried = recordAttempt(recordAttempt(pending));

      expect(retried.attempts, equals(2));
      expect(pending.attempts, equals(0));
      expect(retried.status, equals(OutboxStatus.pending));
      expect(retried.vote, same(pending.vote));
      expect(retried.enqueuedAt, equals(now));
    });
  });

  group('rejectVote', () {
    const reason = ResolutionClosedError();

    test('moves a pending vote to the rejected state, '
        'keeping its history and giving the reason', () {
      final pending = recordAttempt(createPendingVote(aVote(), at(-1000)));

      final rejected = rejectVote(pending, reason, now);

      expect(rejected.status, equals(OutboxStatus.rejected));
      expect(
        rejected,
        equals(
          RejectedVote(
            vote: aVote(),
            enqueuedAt: at(-1000),
            attempts: 1,
            reason: reason,
            rejectedAt: now,
          ),
        ),
      );
    });

    test('can carry the undeliverable reason', () {
      final rejected = rejectVote(aPendingVote(), voteUndeliverable(5), now);

      expect(rejected.reason, equals(voteUndeliverable(5)));
    });

    test('leaves the pending vote untouched', () {
      final pending = aPendingVote();

      rejectVote(pending, reason, now);

      expect(pending.status, equals(OutboxStatus.pending));
      // A pending vote has no reason: the type of the state says so.
      expect(pending, isNot(isA<RejectedVote>()));
      expect(pending, equals(aPendingVote()));
    });
  });

  group('the states', () {
    test('are told apart by their status', () {
      expect(isPending(aPendingVote()), isTrue);
      expect(isRejected(aPendingVote()), isFalse);
      expect(isPending(aRejectedVote()), isFalse);
      expect(isRejected(aRejectedVote()), isTrue);
    });

    test(
      'build a rejected vote that carries its reason and rejection instant',
      () {
        final rejected = aRejectedVote();

        expect(rejected.rejectedAt, equals(at(millisPerMinute)));
        expect(rejected.reason, equals(const ResolutionClosedError()));
      },
    );
  });

  group('restorePendingVote', () {
    test('rebuilds a pending vote read back from storage', () {
      expect(
        unwrap(
          restorePendingVote(vote: aVote(), enqueuedAt: at(-1000), attempts: 3),
        ),
        equals(PendingVote(vote: aVote(), enqueuedAt: at(-1000), attempts: 3)),
      );
    });

    for (final (attempts, rule) in <(num, ValidationRule)>[
      (-1, ValidationRule.outOfRange),
      (1000001, ValidationRule.outOfRange),
      (1.5, ValidationRule.notAnInteger),
    ]) {
      test('rejects the attempt count ${formatPretty(attempts)}', () {
        expect(
          restorePendingVote(
            vote: aVote(),
            enqueuedAt: now,
            attempts: attempts,
          ),
          equals(err(validationError(ValidationField.attemptCount, rule))),
        );
      });
    }
  });
}
