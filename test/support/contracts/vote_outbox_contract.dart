import 'dart:async';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/ports/vote_outbox.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:test/test.dart';

import '../builders/builders.dart';
import 'support.dart';

/// What the suite needs besides the port: a way to fail a statement, and to
/// close and reopen.
final class VoteOutboxHarness {
  /// Creates a harness.
  const new({
    required this.outbox,
    this.failNextStatement,
    this.reopen,
    this.plantUnreadable,
  });

  /// The adapter under test.
  final VoteOutbox outbox;

  /// Makes the next statement the outbox sends to its storage fail, once. Only
  /// an outbox that has a storage to fail provides it
  /// (`StoreContractOptions.failsStatements`).
  final void Function()? failNextStatement;

  /// Closes the outbox and opens it again on the same storage, as a new start
  /// of the app would, and returns the new one. Only an outbox whose content
  /// survives provides it (`StoreContractOptions.survivesReopen`).
  final Future<VoteOutbox> Function()? reopen;

  /// Puts an entry of this voter, under this idempotency key, in the storage in
  /// a state that no longer reads back as a vote, behind the back of the
  /// outbox. Only an outbox that can hold one provides it
  /// (`VoteOutboxContractOptions.holdsUnreadable`).
  final FutureOr<void> Function(UserId voter, IdempotencyKey key)?
  plantUnreadable;
}

/// Makes a harness, now or later.
typedef VoteOutboxFactory = FutureOr<VoteOutboxHarness> Function();

/// What the suite can ask of an outbox beyond what any store can.
final class VoteOutboxContractOptions extends StoreContractOptions {
  /// Creates the options.
  const new({
    required super.failsStatements,
    required super.survivesReopen,
    required this.holdsUnreadable,
  });

  /// Whether the outbox can hold an entry that cannot be read as a vote, and
  /// the harness can plant one (`plantUnreadable`). An outbox that holds its
  /// entries as typed values cannot, and the group that pins the quarantine is
  /// shown as skipped for it.
  final bool holdsUnreadable;
}

/// What `list` gives, as the votes alone: most of the suite is about the votes.
Future<Result<List<OutboxVote>, StorageReadFailedError>> _readVotes(
  VoteOutbox outbox,
  UserId voter,
) async => map(await outbox.list(voter), (listing) => listing.votes);

final UserId _voter = aUserId('voter-1');
final UserId _otherVoter = aUserId('voter-2');

Vote _vote(
  String resolution, [
  UserId? voter,
  VoteChoice choice = VoteChoice.forChoice,
]) => aVote(
  resolutionId: aResolutionId(resolution),
  voterId: voter ?? _voter,
  choice: choice,
);

PendingVote _pending(String resolution, [Instant? enqueuedAt, UserId? voter]) =>
    aPendingVote(_vote(resolution, voter), enqueuedAt ?? at(0));

/// The contract of `VoteOutbox`, as a suite any implementation runs: first in,
/// first out, reads scoped by voter, the idempotent writes (`enqueue`,
/// `reject`, `remove`) and the one that is not (`markAttempt`), the two states
/// a vote can be in, and no reference kept to what goes in or out. The factory
/// returns a fresh, empty outbox.
void describeVoteOutboxContract(
  String name,
  VoteOutboxFactory createOutbox,
  VoteOutboxContractOptions options,
) {
  group('$name honours the VoteOutbox contract', () {
    late VoteOutboxHarness harness;
    late VoteOutbox outbox;

    setUp(() async {
      harness = await createOutbox();
      outbox = harness.outbox;
    });

    group('enqueue and list', () {
      test('lists nothing for a voter who has no vote', () async {
        expect(await _readVotes(outbox, _voter), equals(ok(<OutboxVote>[])));
        expect(
          await outbox.findByResolution(aResolutionId('r1'), _voter),
          equals(ok(<OutboxVote>[])),
        );
      });

      test('enqueues a vote and gives it back as it was', () async {
        final queued = aPendingVote(_vote('r1'), at(5));

        expect(
          await outbox.enqueue(queued),
          equals(ok(const EnqueueResult.enqueued())),
        );

        expect(await _readVotes(outbox, _voter), equals(ok([queued])));
      });

      test('keeps the attempts a vote already counts '
          'when it is enqueued', () async {
        final attempted = aPendingVote(
          _vote('r1'),
          at(5),
        ).copyWith(attempts: 3);

        await outbox.enqueue(attempted);

        expect(await _readVotes(outbox, _voter), equals(ok([attempted])));
      });

      test('lists the votes in the order they were enqueued, '
          'which no sort of the votes would give', () async {
        // Enqueued in this order, the votes are in decreasing order of instant
        // and in no order of resolution: a sort by instant (oldest first), by
        // resolution, or by key gives another.
        final first = _pending('r9', at(5000));
        final second = _pending('r1', at(1000));
        final third = _pending('r5', at(-9000));

        await outbox.enqueue(first);
        await outbox.enqueue(second);
        await outbox.enqueue(third);

        expect(
          await _readVotes(outbox, _voter),
          equals(ok([first, second, third])),
        );
      });

      test('answers that a vote with the same key is already queued, '
          'and changes nothing', () async {
        final first = _pending('r1', at(1));
        await outbox.enqueue(first);
        await outbox.enqueue(_pending('r2', at(2)));

        final again = await outbox.enqueue(
          aPendingVote(_vote('r1', _voter, VoteChoice.against), at(3)),
        );

        expect(again, equals(ok(EnqueueResult.alreadyQueued(existing: first))));
        expect(
          await _readVotes(outbox, _voter),
          equals(ok([first, _pending('r2', at(2))])),
        );
      });

      test('holds the key of a rejected vote too: '
          'it answers with the rejected vote', () async {
        await outbox.enqueue(_pending('r1', at(1)));
        await outbox.reject(
          _pending('r1').vote.idempotencyKey,
          const ResolutionClosedError(),
          at(9),
        );
        final rejected = await _readVotes(outbox, _voter);

        final again = await outbox.enqueue(_pending('r1', at(3)));

        expect(
          again,
          equals(
            ok(EnqueueResult.alreadyQueued(existing: valueOf(rejected).first)),
          ),
        );
        expect(await _readVotes(outbox, _voter), equals(rejected));
      });
    });

    group('findByResolution', () {
      test('returns the vote of a resolution whatever its state: '
          'pending, and rejected', () async {
        final queued = _pending('r1', at(1));
        await outbox.enqueue(queued);
        expect(
          await outbox.findByResolution(aResolutionId('r1'), _voter),
          equals(ok([queued])),
        );

        await outbox.reject(
          queued.vote.idempotencyKey,
          const ResolutionClosedError(),
          at(9),
        );

        final found = await outbox.findByResolution(
          aResolutionId('r1'),
          _voter,
        );
        expect(
          found,
          equals(
            ok([rejectVote(queued, const ResolutionClosedError(), at(9))]),
          ),
        );
      });
    });

    group('reads scoped by voter', () {
      test(
        'only ever returns the votes of the voter it is asked for',
        () async {
          final mine = _pending('r1', at(1));
          final theirs = _pending('r1', at(2), _otherVoter);
          final alsoMine = _pending('r2', at(3));
          await outbox.enqueue(mine);
          await outbox.enqueue(theirs);
          await outbox.enqueue(alsoMine);

          expect(
            await _readVotes(outbox, _voter),
            equals(ok([mine, alsoMine])),
          );
          expect(await _readVotes(outbox, _otherVoter), equals(ok([theirs])));
          expect(
            await _readVotes(outbox, aUserId('voter-3')),
            equals(ok(<OutboxVote>[])),
          );
          expect(
            await outbox.findByResolution(aResolutionId('r1'), _voter),
            equals(ok([mine])),
          );
          expect(
            await outbox.findByResolution(aResolutionId('r1'), _otherVoter),
            equals(ok([theirs])),
          );
          expect(
            await outbox.findByResolution(aResolutionId('r2'), _otherVoter),
            equals(ok(<OutboxVote>[])),
          );
        },
      );

      test('queues the same resolution for two voters '
          'without one taking the key of the other', () async {
        final mine = _pending('r1', at(1));
        final theirs = _pending('r1', at(2), _otherVoter);

        expect(
          await outbox.enqueue(mine),
          equals(ok(const EnqueueResult.enqueued())),
        );
        expect(
          await outbox.enqueue(theirs),
          equals(ok(const EnqueueResult.enqueued())),
        );
      });
    });

    group('the whole idempotency key identifies a vote', () {
      // The key is `<length of the resolution id>.<resolution id>.<voter id>`:
      // these pairs make keys that share a long prefix, or differ only in case
      // or in an inner dot.
      const similar = [
        ('r1', 'user-1'),
        ('r1', 'user-10'),
        ('r1', 'user-1.0'),
        ('r1', 'USER-1'),
        ('r1.user-1', 'x'),
        ('r', '1.user-1'),
      ];
      PendingVote queued(
        String resolution,
        String voter, [
        Instant? enqueuedAt,
      ]) =>
          aPendingVote(_vote(resolution, aUserId(voter)), enqueuedAt ?? at(0));

      test('enqueues each of them as a vote of its own, '
          'and lists each one for its voter only', () async {
        for (final (resolution, voter) in similar) {
          expect(
            await outbox.enqueue(queued(resolution, voter)),
            equals(ok(const EnqueueResult.enqueued())),
          );
        }

        for (final (resolution, voter) in similar) {
          expect(
            await _readVotes(outbox, aUserId(voter)),
            equals(ok([queued(resolution, voter)])),
          );
        }
      });

      test('treats resolution ids that differ only in case '
          'as two resolutions', () async {
        await outbox.enqueue(queued('r1', 'user-1', at(1)));

        expect(
          await outbox.enqueue(queued('R1', 'user-1', at(2))),
          equals(ok(const EnqueueResult.enqueued())),
        );
        expect(
          await outbox.findByResolution(aResolutionId('R1'), aUserId()),
          equals(ok([queued('R1', 'user-1', at(2))])),
        );
      });

      test('removes, counts an attempt on, and rejects only the vote '
          'whose key it is given', () async {
        for (final (resolution, voter) in similar) {
          await outbox.enqueue(queued(resolution, voter));
        }
        final [first, second, ...others] = similar;
        final target = queued(first.$1, first.$2);

        await outbox.markAttempt(target.vote.idempotencyKey);
        await outbox.reject(
          queued(second.$1, second.$2).vote.idempotencyKey,
          const ResolutionClosedError(),
          at(9),
        );
        await outbox.remove(
          queued(others[0].$1, others[0].$2).vote.idempotencyKey,
        );

        expect(
          await _readVotes(outbox, aUserId(first.$2)),
          equals(ok([target.copyWith(attempts: 1)])),
        );
        final rejected = await _readVotes(outbox, aUserId(second.$2));
        expect(
          valueOf(rejected).map((entry) => entry.status).toList(),
          equals([OutboxStatus.rejected]),
        );
        expect(
          await _readVotes(outbox, aUserId(others[0].$2)),
          equals(ok(<OutboxVote>[])),
        );
        for (final (resolution, voter) in others.skip(1)) {
          expect(
            await _readVotes(outbox, aUserId(voter)),
            equals(ok([queued(resolution, voter)])),
          );
        }
      });
    });

    group('markAttempt', () {
      test('counts one more attempt every time it is called: '
          'it is not idempotent', () async {
        final queued = _pending('r1');
        await outbox.enqueue(queued);

        await outbox.markAttempt(queued.vote.idempotencyKey);
        await outbox.markAttempt(queued.vote.idempotencyKey);

        expect(
          await _readVotes(outbox, _voter),
          equals(ok([queued.copyWith(attempts: 2)])),
        );
      });

      test('does nothing for an unknown key, '
          'and for a vote that is rejected', () async {
        final rejected = _pending('r1');
        await outbox.enqueue(rejected);
        await outbox.reject(
          rejected.vote.idempotencyKey,
          const ResolutionClosedError(),
          at(9),
        );
        final before = await _readVotes(outbox, _voter);

        expect(
          await outbox.markAttempt(rejected.vote.idempotencyKey),
          equals(ok<void>(null)),
        );
        expect(
          await outbox.markAttempt(_vote('unknown').idempotencyKey),
          equals(ok<void>(null)),
        );

        expect(await _readVotes(outbox, _voter), equals(before));
      });
    });

    group('reject', () {
      test('moves a pending vote to the rejected state '
          'with its reason and instant, in the same place', () async {
        final first = _pending('r1', at(1));
        final second = _pending('r2', at(2));
        final third = _pending('r3', at(3));
        for (final queued in [first, second, third]) {
          await outbox.enqueue(queued);
        }
        const reason = ResolutionClosedError();

        expect(
          await outbox.reject(second.vote.idempotencyKey, reason, at(10)),
          equals(ok<void>(null)),
        );

        final expected = RejectedVote(
          vote: second.vote,
          enqueuedAt: second.enqueuedAt,
          attempts: 0,
          reason: reason,
          rejectedAt: at(10),
        );
        expect(
          await _readVotes(outbox, _voter),
          equals(ok([first, expected, third])),
        );
      });

      test('keeps the attempts a vote counted, '
          'and every kind of reason with its fields', () async {
        final queued = _pending('r1');
        final other = _pending('r2');
        await outbox.enqueue(queued);
        await outbox.enqueue(other);
        await outbox.markAttempt(queued.vote.idempotencyKey);
        await outbox.markAttempt(queued.vote.idempotencyKey);
        final undeliverable = voteUndeliverable(5);
        const alreadyVoted = AlreadyVotedError(
          source: AlreadyVotedSource.recorded,
        );

        await outbox.reject(queued.vote.idempotencyKey, undeliverable, at(10));
        await outbox.reject(other.vote.idempotencyKey, alreadyVoted, at(11));

        expect(
          await _readVotes(outbox, _voter),
          equals(
            ok([
              rejectVote(queued.copyWith(attempts: 2), undeliverable, at(10)),
              rejectVote(other, alreadyVoted, at(11)),
            ]),
          ),
        );
      });

      test('rejects once: a second rejection, '
          'and an unknown key, change nothing', () async {
        final queued = _pending('r1');
        await outbox.enqueue(queued);
        const reason = ResolutionClosedError();
        await outbox.reject(queued.vote.idempotencyKey, reason, at(10));
        final before = await _readVotes(outbox, _voter);

        expect(
          await outbox.reject(
            queued.vote.idempotencyKey,
            const NoVotingRightsError(),
            at(20),
          ),
          equals(ok<void>(null)),
        );
        expect(
          await outbox.reject(_vote('unknown').idempotencyKey, reason, at(30)),
          equals(ok<void>(null)),
        );

        expect(await _readVotes(outbox, _voter), equals(before));
      });
    });

    group('remove', () {
      test('removes a vote, pending or rejected, '
          'and leaves the others in order', () async {
        final first = _pending('r1', at(1));
        final rejected = _pending('r2', at(2));
        final last = _pending('r3', at(3));
        for (final queued in [first, rejected, last]) {
          await outbox.enqueue(queued);
        }
        await outbox.reject(
          rejected.vote.idempotencyKey,
          const ResolutionClosedError(),
          at(9),
        );

        await outbox.remove(rejected.vote.idempotencyKey);
        await outbox.remove(first.vote.idempotencyKey);

        expect(await _readVotes(outbox, _voter), equals(ok([last])));
      });

      test('succeeds for an unknown key, '
          'and frees the key of a vote it removed', () async {
        final queued = _pending('r1');
        await outbox.enqueue(queued);

        expect(
          await outbox.remove(_vote('unknown').idempotencyKey),
          equals(ok<void>(null)),
        );
        await outbox.remove(queued.vote.idempotencyKey);
        await outbox.remove(queued.vote.idempotencyKey);

        expect(
          await outbox.enqueue(queued),
          equals(ok(const EnqueueResult.enqueued())),
        );
      });

      test('does not touch the votes of another voter', () async {
        final mine = _pending('r1', at(1));
        final theirs = _pending('r1', at(2), _otherVoter);
        await outbox.enqueue(mine);
        await outbox.enqueue(theirs);

        await outbox.remove(mine.vote.idempotencyKey);

        expect(await _readVotes(outbox, _otherVoter), equals(ok([theirs])));
      });
    });

    // An outbox without a storage to fail, or with nothing to reopen, skips
    // these: they show as skipped.
    group('a statement that fails', () {
      void failNext() {
        final fail = harness.failNextStatement;
        if (fail == null) {
          throw StateError('The harness cannot fail a statement.');
        }
        fail();
      }

      test('turns an enqueue that fails into a storage error, '
          'queues nothing, and enqueues once it works', () async {
        failNext();
        final failed = await outbox.enqueue(_pending('r1', at(1)));

        expect(errorCodeOf(failed), equals(StorageErrorCode.writeFailed.value));
        expect(await _readVotes(outbox, _voter), equals(ok(<OutboxVote>[])));
        expect(
          await outbox.enqueue(_pending('r1', at(1))),
          equals(ok(const EnqueueResult.enqueued())),
        );
      });

      test('turns a read that fails into a storage error, '
          'and reads again afterwards', () async {
        final queued = _pending('r1', at(1));
        await outbox.enqueue(queued);

        failNext();
        final failedList = await _readVotes(outbox, _voter);
        failNext();
        final failedFind = await outbox.findByResolution(
          aResolutionId('r1'),
          _voter,
        );

        expect(
          errorCodeOf(failedList),
          equals(StorageErrorCode.readFailed.value),
        );
        expect(
          errorCodeOf(failedFind),
          equals(StorageErrorCode.readFailed.value),
        );
        expect(await _readVotes(outbox, _voter), equals(ok([queued])));
      });

      test('turns an attempt that cannot be counted into a storage error, '
          'and counts nothing', () async {
        final queued = _pending('r1', at(1));
        await outbox.enqueue(queued);

        failNext();
        final failed = await outbox.markAttempt(queued.vote.idempotencyKey);

        expect(errorCodeOf(failed), equals(StorageErrorCode.writeFailed.value));
        expect(await _readVotes(outbox, _voter), equals(ok([queued])));
      });

      test('turns a rejection that cannot be written into a storage error, '
          'and leaves the vote pending', () async {
        final queued = _pending('r1', at(1));
        await outbox.enqueue(queued);

        failNext();
        final failed = await outbox.reject(
          queued.vote.idempotencyKey,
          const ResolutionClosedError(),
          at(9),
        );

        expect(errorCodeOf(failed), equals(StorageErrorCode.writeFailed.value));
        expect(await _readVotes(outbox, _voter), equals(ok([queued])));
      });

      test('turns a removal that fails into a storage error, '
          'and keeps the vote', () async {
        final queued = _pending('r1', at(1));
        await outbox.enqueue(queued);

        failNext();
        final failed = await outbox.remove(queued.vote.idempotencyKey);

        expect(errorCodeOf(failed), equals(StorageErrorCode.writeFailed.value));
        expect(await _readVotes(outbox, _voter), equals(ok([queued])));
      });
    }, skip: !options.failsStatements);

    group('an entry that cannot be read as a vote', () {
      final ownKey = _vote('rx').idempotencyKey;
      Future<void> plant([UserId? voter, IdempotencyKey? key]) async {
        final plantEntry = harness.plantUnreadable;
        if (plantEntry == null) {
          throw StateError('The harness cannot plant an unreadable entry.');
        }
        await plantEntry(voter ?? _voter, key ?? ownKey);
      }

      Future<int> countOf([UserId? voter]) async =>
          valueOf(await outbox.list(voter ?? _voter)).unreadable;

      test(
        'counts it, and lists the votes that can be read without it',
        () async {
          final queued = _pending('r1', at(1));
          await outbox.enqueue(queued);
          await plant();

          final listed = await outbox.list(_voter);

          expect(
            listed,
            equals(ok(OutboxListing(votes: [queued], unreadable: 1))),
          );
        },
      );

      test('says there is none when there is none', () async {
        await outbox.enqueue(_pending('r1'));

        expect(
          await outbox.list(_voter),
          equals(ok(OutboxListing(votes: [_pending('r1')], unreadable: 0))),
        );
      });

      test('keeps it through any number of reads: '
          'reading never deletes it', () async {
        await plant();

        for (var reads = 0; reads < 3; reads += 1) {
          await outbox.list(_voter);
          await outbox.findByResolution(aResolutionId('rx'), _voter);
        }

        expect(await countOf(), equals(1));
      });

      test('counts only the entries of the voter asked about', () async {
        await plant(_voter, _vote('r1').idempotencyKey);
        await plant(_voter, _vote('r2').idempotencyKey);
        await plant(_otherVoter, _vote('r1', _otherVoter).idempotencyKey);

        expect(await countOf(_voter), equals(2));
        expect(await countOf(_otherVoter), equals(1));
        expect(await countOf(aUserId('voter-3')), equals(0));
      });

      test('does not find it as a vote on a resolution', () async {
        await plant();

        expect(
          await outbox.findByResolution(aResolutionId('rx'), _voter),
          equals(ok(<OutboxVote>[])),
        );
      });

      test('is not overwritten by a vote queued under its key: '
          'the vote is not queued, and says why', () async {
        await plant();

        final queued = await outbox.enqueue(aPendingVote(_vote('rx'), at(3)));

        expect(queued, equals(ok(const EnqueueResult.heldByUnreadable())));
        expect(
          await outbox.list(_voter),
          equals(ok(const OutboxListing(votes: <OutboxVote>[], unreadable: 1))),
        );
      });

      test('is not touched by a rejection, an attempt '
          'or a removal under its key', () async {
        await plant();

        await outbox.markAttempt(ownKey);
        await outbox.reject(ownKey, const ResolutionClosedError(), at(9));
        final removed = await outbox.remove(ownKey);

        expect(removed, equals(ok<void>(null)));
        expect(
          await outbox.list(_voter),
          equals(ok(const OutboxListing(votes: <OutboxVote>[], unreadable: 1))),
        );
      });

      test('does not stop the votes around it '
          'from being queued, rejected and removed', () async {
        await plant();
        final first = _pending('r1', at(1));
        final second = _pending('r2', at(2));
        await outbox.enqueue(first);
        await outbox.enqueue(second);

        await outbox.reject(
          first.vote.idempotencyKey,
          voteUndeliverable(5),
          at(9),
        );
        await outbox.remove(second.vote.idempotencyKey);

        expect(
          await outbox.list(_voter),
          equals(
            ok(
              OutboxListing(
                votes: [rejectVote(first, voteUndeliverable(5), at(9))],
                unreadable: 1,
              ),
            ),
          ),
        );
      });

      group('discarding', () {
        test('removes the entries of the voter, says how many, '
            'and leaves the votes that can be read', () async {
          final queued = _pending('r1', at(1));
          await outbox.enqueue(queued);
          await plant(_voter, _vote('r8').idempotencyKey);
          await plant(_voter, _vote('r9').idempotencyKey);

          final discarded = await outbox.discardUnreadable(_voter);

          expect(discarded, equals(ok(2)));
          expect(
            await outbox.list(_voter),
            equals(ok(OutboxListing(votes: [queued], unreadable: 0))),
          );
        });

        test('leaves the entries of the other voters', () async {
          await plant(_voter, _vote('r1').idempotencyKey);
          await plant(_otherVoter, _vote('r1', _otherVoter).idempotencyKey);

          await outbox.discardUnreadable(_voter);

          expect(await countOf(_voter), equals(0));
          expect(await countOf(_otherVoter), equals(1));
        });

        test('says zero when there is nothing to discard, '
            'now and when asked again', () async {
          expect(await outbox.discardUnreadable(_voter), equals(ok(0)));
          await plant();
          expect(await outbox.discardUnreadable(_voter), equals(ok(1)));
          expect(await outbox.discardUnreadable(_voter), equals(ok(0)));
        });

        test('makes room for the vote that was refused: '
            'it can be queued afterwards', () async {
          await plant();
          await outbox.discardUnreadable(_voter);

          final queued = await outbox.enqueue(aPendingVote(_vote('rx'), at(3)));

          expect(queued, equals(ok(const EnqueueResult.enqueued())));
          expect(
            await _readVotes(outbox, _voter),
            equals(ok([aPendingVote(_vote('rx'), at(3))])),
          );
        });
      });

      group('and a statement that fails', () {
        test('turns a discard that fails into a storage error, '
            'and discards nothing', () async {
          await plant();

          final fail = harness.failNextStatement;
          if (fail == null) {
            throw StateError('No statement to fail.');
          }
          fail();
          final failed = await outbox.discardUnreadable(_voter);

          expect(isOk(failed), isFalse);
          expect(
            errorCodeOf(failed),
            equals(StorageErrorCode.writeFailed.value),
          );
          expect(await countOf(), equals(1));
        });
      }, skip: !options.failsStatements);

      group('and the outbox opened again', () {
        test('still holds it, and still counts it', () async {
          await plant();
          final reopen = harness.reopen;
          if (reopen == null) {
            throw StateError('The harness cannot reopen.');
          }

          final reopened = await reopen();

          expect(
            await reopened.list(_voter),
            equals(
              ok(const OutboxListing(votes: <OutboxVote>[], unreadable: 1)),
            ),
          );
        });
      }, skip: !options.survivesReopen);
    }, skip: !options.holdsUnreadable);

    group('closed and opened again', () {
      Future<VoteOutbox> reopen() {
        final reopenOutbox = harness.reopen;
        if (reopenOutbox == null) {
          throw StateError('The harness cannot reopen the outbox.');
        }
        return reopenOutbox();
      }

      test('gives back the votes of every voter, pending and rejected, '
          'in the order they were enqueued', () async {
        final first = _pending('r9', at(5000));
        final second = _pending('r1', at(1000));
        final third = _pending('r5', at(-9000), _otherVoter);
        final last = _pending('r3', at(0));
        for (final queued in [first, second, third, last]) {
          await outbox.enqueue(queued);
        }
        await outbox.markAttempt(first.vote.idempotencyKey);
        await outbox.markAttempt(first.vote.idempotencyKey);
        final reason = voteUndeliverable(5);
        await outbox.reject(second.vote.idempotencyKey, reason, at(10));

        final reopened = await reopen();

        expect(
          await _readVotes(reopened, _voter),
          equals(
            ok([
              first.copyWith(attempts: 2),
              rejectVote(second, reason, at(10)),
              last,
            ]),
          ),
        );
        expect(await _readVotes(reopened, _otherVoter), equals(ok([third])));
        expect(
          await reopened.findByResolution(aResolutionId('r1'), _voter),
          equals(ok([rejectVote(second, reason, at(10))])),
        );
      });

      test('keeps every kind of reason with its fields', () async {
        final reasons = <RejectionReason>[
          ResolutionNotFoundError(resolutionId: aResolutionId('gone')),
          const NotAParticipantError(),
          const NoVotingRightsError(),
          const ResolutionClosedError(),
          const VotingWindowOverError(),
          const AlreadyVotedError(source: AlreadyVotedSource.queued),
          voteUndeliverable(3),
        ];
        final queued = [
          for (final (number, _) in reasons.indexed)
            _pending('r$number', at(number)),
        ];
        for (final entry in queued) {
          await outbox.enqueue(entry);
        }
        for (final (number, reason) in reasons.indexed) {
          await outbox.reject(
            queued[number].vote.idempotencyKey,
            reason,
            at(50),
          );
        }

        final reopened = await reopen();

        expect(
          await _readVotes(reopened, _voter),
          equals(
            ok([
              for (final (number, entry) in queued.indexed)
                rejectVote(entry, reasons[number], at(50)),
            ]),
          ),
        );
      });

      test('still holds the key of a vote: '
          'enqueueing it again changes nothing', () async {
        final queued = _pending('r1', at(1));
        await outbox.enqueue(queued);

        final reopened = await reopen();

        expect(
          await reopened.enqueue(_pending('r1', at(2))),
          equals(ok(EnqueueResult.alreadyQueued(existing: queued))),
        );
        expect(await _readVotes(reopened, _voter), equals(ok([queued])));
      });

      test('goes on in the same order: a vote enqueued afterwards '
          'comes after the others, even those removed', () async {
        final first = _pending('r1', at(9000));
        final second = _pending('r2', at(8000));
        await outbox.enqueue(first);
        await outbox.enqueue(second);
        await outbox.remove(second.vote.idempotencyKey);

        final reopened = await reopen();
        final third = _pending('r3', at(-5000));
        await reopened.enqueue(third);

        expect(await _readVotes(reopened, _voter), equals(ok([first, third])));
      });

      test('does not give back a vote that was removed '
          'before it was closed', () async {
        final queued = _pending('r1', at(1));
        await outbox.enqueue(queued);
        await outbox.remove(queued.vote.idempotencyKey);

        final reopened = await reopen();

        expect(await _readVotes(reopened, _voter), equals(ok(<OutboxVote>[])));
        expect(
          await reopened.enqueue(queued),
          equals(ok(const EnqueueResult.enqueued())),
        );
      });
    }, skip: !options.survivesReopen);

    group('writers at the same time', () {
      test('enqueues a vote once when several callers enqueue it together, '
          'and tells each what happened', () async {
        final answers = await Future.wait([
          for (final number in [1, 2, 3, 4, 5, 6, 7, 8])
            outbox.enqueue(_pending('r1', at(number))),
        ]);

        final outcomes = [
          for (final answer in answers)
            switch (answer) {
              Ok(:final value) => value.outcome,
              Err() => null,
            },
        ];
        expect(
          outcomes.where((outcome) => outcome == EnqueueOutcome.enqueued),
          hasLength(1),
        );
        expect(
          outcomes.where((outcome) => outcome == EnqueueOutcome.alreadyQueued),
          hasLength(7),
        );
        final listed = await _readVotes(outbox, _voter);
        expect(valueOf(listed), hasLength(1));
      });

      test('tells everyone that lost the race which vote won it', () async {
        final answers = await Future.wait([
          for (final number in [1, 2, 3])
            outbox.enqueue(_pending('r1', at(number))),
        ]);
        final listed = await _readVotes(outbox, _voter);
        final winner = valueOf(listed).first;

        for (final answer in answers) {
          if (answer case Ok(:final value) when value is AlreadyQueued) {
            expect(value.existing, equals(winner));
          }
        }
      });

      test(
        'queues every vote when different votes are enqueued together',
        () async {
          final queued = [
            for (final number in [1, 2, 3, 4, 5, 6])
              _pending('r$number', at(number)),
          ];

          await Future.wait([
            for (final entry in queued) outbox.enqueue(entry),
          ]);

          final listed = valueOf(await _readVotes(outbox, _voter));
          expect(listed, hasLength(queued.length));
          for (final entry in queued) {
            expect(listed, contains(entry));
          }
        },
      );

      test('counts every attempt when attempts are marked together: '
          'none is lost', () async {
        final queued = _pending('r1', at(1));
        await outbox.enqueue(queued);

        await Future.wait([
          for (var number = 1; number <= 10; number += 1)
            outbox.markAttempt(queued.vote.idempotencyKey),
        ]);

        expect(
          await _readVotes(outbox, _voter),
          equals(ok([queued.copyWith(attempts: 10)])),
        );
      });

      test('ends in a state a vote can be in '
          'when a rejection and an attempt run together', () async {
        final queued = _pending('r1', at(1));
        await outbox.enqueue(queued);

        await Future.wait<Result<void, StorageWriteFailedError>>([
          outbox.markAttempt(queued.vote.idempotencyKey),
          outbox.reject(
            queued.vote.idempotencyKey,
            const ResolutionClosedError(),
            at(9),
          ),
          outbox.markAttempt(queued.vote.idempotencyKey),
        ]);

        final listed = await _readVotes(outbox, _voter);
        expect(valueOf(listed).first.status, equals(OutboxStatus.rejected));
      });
    });

    group('keeps no reference to the objects that go in or out', () {
      // Three of the four checks have no Dart scenario: a vote, an entry and a
      // reason have no list to change in place, and no setter
      // (docs/parity/exceptions.md).
      test('is not changed by a change of the votes '
          'after they were listed', () async {
        await outbox.enqueue(_pending('r1'));
        final listed = await _readVotes(outbox, _voter);

        // The entries are immutable: only the list could be changed in place,
        // and it refuses it.
        expectRefused(() => valueOf(listed).clear());

        expect(await _readVotes(outbox, _voter), equals(ok([_pending('r1')])));
        expect(
          await outbox.findByResolution(aResolutionId('r1'), _voter),
          equals(ok([_pending('r1')])),
        );
      });
    });

    test('lists a rejected vote as the entry '
        'the test builders produce for one', () async {
      final rejected = aRejectedVote(_vote('r1'));
      final queued = aPendingVote(_vote('r1'), rejected.enqueuedAt);
      await outbox.enqueue(queued);
      await outbox.reject(
        queued.vote.idempotencyKey,
        rejected.reason,
        rejected.rejectedAt,
      );

      expect(await _readVotes(outbox, _voter), equals(ok([rejected])));
    });
  });
}
