import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/use_cases/votes/discard_unreadable_votes.dart';
import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import '../../support/create_fakes.dart';
import '../../support/fake_monitoring.dart';
import '../../support/fake_vote_outbox.dart';

final UserId _own = aUserId();
final UserId _other = aUserId('user-2');

void main() {
  group('DiscardUnreadableVotes', () {
    test('deletes the entries of the signed-in user that cannot be read, '
        'and says how many', () async {
      final fakes = createFakes();
      fakes.outbox.seedUnreadable(_own, 'k1');
      fakes.outbox.seedUnreadable(_own, 'k2');

      final result = await DiscardUnreadableVotes(fakes).execute();

      expect(result, equals(ok(2)));
      expect(fakes.outbox.unreadableSnapshot(), equals(<UnreadableEntry>[]));
    });

    test(
      'leaves the votes that can be read, and the entries of another user',
      () async {
        final fakes = createFakes();
        final queued = aPendingVote(aVote());
        fakes.outbox.seed([queued]);
        fakes.outbox.seedUnreadable(_own, 'k1');
        fakes.outbox.seedUnreadable(_other, 'k2');

        await DiscardUnreadableVotes(fakes).execute();

        expect(fakes.outbox.snapshot(), equals(<OutboxVote>[queued]));
        expect(
          fakes.outbox.unreadableSnapshot(),
          equals([(voterId: _other, key: 'k2')]),
        );
      },
    );

    test(
      'says zero when there is nothing to discard, and when asked again',
      () async {
        final fakes = createFakes();
        fakes.outbox.seedUnreadable(_own, 'k1');
        final useCase = DiscardUnreadableVotes(fakes);

        expect(await useCase.execute(), equals(ok(1)));
        expect(await useCase.execute(), equals(ok(0)));
      },
    );

    test('records that the user asked for it, with the count and nothing '
        'that identifies a vote', () async {
      final fakes = createFakes();
      fakes.outbox.seedUnreadable(_own, 'k1');

      await DiscardUnreadableVotes(fakes).execute();

      expect(
        fakes.monitoring.logs,
        equals([
          const LogRecord(
            level: LogLevel.warn,
            event: MonitoringEvent.unreadableVotesDiscarded,
            attributes: {LogAttribute.discarded: 1},
          ),
        ]),
      );
    });

    test(
      'does not report the count to somebody else who signed in meanwhile',
      () async {
        final fakes = createFakes();
        fakes.outbox.seedUnreadable(_own, 'k1');
        fakes.outbox.onRequest = () {
          fakes.auth.session = aSession(user: aUser(id: _other));
        };

        expect(
          await DiscardUnreadableVotes(fakes).execute(),
          equals(err(sessionChanged())),
        );
        expect(fakes.monitoring.logs, equals(<LogRecord>[]));
      },
    );

    test('does not report the count once the app is locked', () async {
      final fakes = createFakes();
      fakes.outbox.seedUnreadable(_own, 'k1');
      fakes.outbox.onRequest = fakes.appLock.lock;

      expect(
        await DiscardUnreadableVotes(fakes).execute(),
        equals(err(appLocked())),
      );
    });

    test('returns the storage error when the entries cannot be deleted, and '
        'they stay', () async {
      final fakes = createFakes();
      fakes.outbox.seedUnreadable(_own, 'k1');
      fakes.outbox.discardFailure = storageWriteFailed();

      expect(
        await DiscardUnreadableVotes(fakes).execute(),
        equals(err(storageWriteFailed())),
      );
      expect(fakes.outbox.unreadableSnapshot(), hasLength(1));
      expect(fakes.monitoring.logs, equals(<LogRecord>[]));
    });

    test(
      'requires a valid session, and discards nothing without one',
      () async {
        final fakes = createFakes();
        fakes.outbox.seedUnreadable(_own, 'k1');
        final useCase = DiscardUnreadableVotes(fakes);

        fakes.auth.session = null;
        expect(await useCase.execute(), equals(err(notAuthenticated())));
        fakes.auth.session = aSession(expiresAt: now);
        expect(await useCase.execute(), equals(err(sessionExpired())));
        fakes.auth.session = aSession();
        fakes.appLock.lock();
        expect(await useCase.execute(), equals(err(appLocked())));

        expect(fakes.outbox.unreadableSnapshot(), hasLength(1));
      },
    );
  });
}
