import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';

void main() {
  group('idempotencyKeyOf', () {
    test(
      'is deterministic: the same resolution and voter give the same key',
      () {
        expect(
          idempotencyKeyOf(aResolutionId('r1'), aUserId('u1')),
          equals(idempotencyKeyOf(aResolutionId('r1'), aUserId('u1'))),
        );
      },
    );

    test('differs when the resolution or the voter differs', () {
      final key = idempotencyKeyOf(aResolutionId('r1'), aUserId('u1'));

      expect(
        idempotencyKeyOf(aResolutionId('r2'), aUserId('u1')),
        isNot(equals(key)),
      );
      expect(
        idempotencyKeyOf(aResolutionId('r1'), aUserId('u2')),
        isNot(equals(key)),
      );
    });

    test(
      'does not depend on the choice: a member votes once per resolution',
      () {
        Vote vote(VoteChoice choice) => createVote(
          VoteInput(
            resolutionId: aResolutionId(),
            meetingId: aMeetingId(),
            voterId: aUserId(),
            choice: choice,
            castAt: now,
          ),
        );

        expect(
          vote(VoteChoice.forChoice).idempotencyKey,
          equals(vote(VoteChoice.against).idempotencyKey),
        );
      },
    );

    test('cannot be confused by ids that contain the separator', () {
      expect(
        idempotencyKeyOf(aResolutionId('a.b'), aUserId('c')),
        isNot(equals(idempotencyKeyOf(aResolutionId('a'), aUserId('b.c')))),
      );
      expect(
        idempotencyKeyOf(aResolutionId('1.a'), aUserId('b')),
        isNot(equals(idempotencyKeyOf(aResolutionId('1'), aUserId('a.b')))),
      );
    });

    test('never gives the same key to two different pairs of ids', () {
      const alphabet = ['a', '.', '1', ':', '%'];
      final everyId = [
        for (final first in alphabet) ...[
          first,
          for (final second in alphabet) '$first$second',
          for (final second in alphabet)
            for (final third in alphabet) '$first$second$third',
        ],
      ];
      // "." and ".." are not identifiers (they are directories in a path).
      final ids = everyId.where((id) => id != '.' && id != '..').toList();
      final keys = [
        for (final resolution in ids)
          for (final voter in ids)
            idempotencyKeyOf(aResolutionId(resolution), aUserId(voter)),
      ];

      expect(keys.toSet().length, equals(ids.length * ids.length));
    });

    test('is built from text only: it gives a key for any text, '
        'even for ids the parsers refuse', () {
      // The parsers refuse a lone surrogate, but the key is a pure function
      // of two strings: whatever reaches it is turned into a key.
      const lone = '\uD800' as ResolutionId;
      const loneVoter = '\uD800' as UserId;

      expect(() => idempotencyKeyOf(lone, loneVoter), returnsNormally);
      expect(
        idempotencyKeyOf(lone, aUserId('u')),
        isNot(equals(idempotencyKeyOf('\uD801' as ResolutionId, aUserId('u')))),
      );
    });
  });

  group('createVote', () {
    test('holds the fields it is given and the derived key', () {
      final vote = createVote(
        VoteInput(
          resolutionId: aResolutionId(),
          meetingId: aMeetingId(),
          voterId: aUserId(),
          choice: VoteChoice.abstain,
          castAt: now,
        ),
      );

      expect(
        vote,
        equals(
          Vote(
            resolutionId: aResolutionId(),
            meetingId: aMeetingId(),
            voterId: aUserId(),
            choice: VoteChoice.abstain,
            castAt: now,
            idempotencyKey: idempotencyKeyOf(aResolutionId(), aUserId()),
          ),
        ),
      );
    });
  });
}
