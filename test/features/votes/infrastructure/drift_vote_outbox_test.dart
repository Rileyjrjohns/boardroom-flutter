import 'package:boardroom/app/persistence/migrations.dart' as schema;
import 'package:boardroom/app/persistence/schema.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/votes/application/ports/vote_outbox.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/infrastructure/drift_vote_outbox.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/contracts/vote_outbox_contract.dart';
import '../../../support/fakes/fake_monitoring.dart';
import '../../../support/infrastructure/encrypted_test_database.dart';
import '../../../support/infrastructure/test_database.dart';

/// The outbox over a real SQLite database, and what the contract suite needs to
/// wreck it.
VoteOutboxHarness _harnessOf(TestDatabase test, FakeMonitoring monitoring) {
  final outbox = DriftVoteOutbox(
    database: test.database,
    monitoring: monitoring,
  );
  return VoteOutboxHarness(
    outbox: outbox,
    failNextStatement: test.faults.failNext,
    reopen: test.file == null
        ? null
        : () async {
            final reopened = await test.reopen();
            return _harnessOf(reopened, monitoring).outbox;
          },
    // An entry the outbox cannot read as a vote: a choice nobody can make.
    plantUnreadable: (voter, key) => test.database.run(
      'INSERT INTO $_votes '
      '($_keyColumn, $_voterColumn, $_resolutionColumn, $_meetingColumn, '
      '$_choiceColumn, $_castAtColumn, $_enqueuedAtColumn, $_attemptsColumn, '
      '$_statusColumn) '
      "VALUES (?, ?, 'planted', 'planted', 'maybe', 1, 1, 0, 'pending')",
      [key, voter],
    ),
  );
}

String get _votes => StoredTable.outboxVotes.value;
String get _sequenceColumn => StoredColumn.sequence.value;
String get _keyColumn => StoredColumn.idempotencyKey.value;
String get _voterColumn => StoredColumn.voterId.value;
String get _resolutionColumn => StoredColumn.resolutionId.value;
String get _meetingColumn => StoredColumn.meetingId.value;
String get _choiceColumn => StoredColumn.choice.value;
String get _castAtColumn => StoredColumn.castAt.value;
String get _enqueuedAtColumn => StoredColumn.enqueuedAt.value;
String get _attemptsColumn => StoredColumn.attempts.value;
String get _statusColumn => StoredColumn.status.value;
String get _reasonColumn => StoredColumn.rejectionReason.value;
String get _rejectedAtColumn => StoredColumn.rejectedAt.value;

// What the contract cannot say: the shape of the rows, the checks of the
// database, and what the outbox does with a row that is not a vote.

final UserId _voter = aUserId('voter-1');

PendingVote _pendingVote(String resolution, [Instant? enqueuedAt]) =>
    aPendingVote(
      aVote(resolutionId: aResolutionId(resolution), voterId: _voter),
      enqueuedAt ?? at(0),
    );

Future<List<Map<String, Object?>>> _rows(TestDatabase test) =>
    test.database.all('SELECT * FROM $_votes ORDER BY $_sequenceColumn');

void main() {
  final directory = databaseDirectory();

  describeVoteOutboxContract(
    'DriftVoteOutbox',
    () async => _harnessOf(await openTestDatabase(directory), FakeMonitoring()),
    const VoteOutboxContractOptions(
      failsStatements: true,
      survivesReopen: true,
      holdsUnreadable: true,
    ),
  );

  // The same suite on a database in memory, which has no file to open again.
  describeVoteOutboxContract(
    'DriftVoteOutbox in memory',
    () async => _harnessOf(await openTestDatabase(), FakeMonitoring()),
    const VoteOutboxContractOptions(
      failsStatements: true,
      survivesReopen: false,
      holdsUnreadable: true,
    ),
  );

  // The same suite on the database the app opens: encrypted, with the key of
  // the secure storage.
  describeVoteOutboxContract(
    'DriftVoteOutbox encrypted',
    () async => _harnessOf(
      await openEncryptedTestDatabase(directory),
      FakeMonitoring(),
    ),
    const VoteOutboxContractOptions(
      failsStatements: true,
      survivesReopen: true,
      holdsUnreadable: true,
    ),
  );

  group('DriftVoteOutbox, on the encrypted database', () {
    test('keeps the votes in a file that is no SQLite database '
        'to whoever has not the key', () async {
      final test = await openEncryptedTestDatabase(directory);
      final outbox = DriftVoteOutbox(
        database: test.database,
        monitoring: FakeMonitoring(),
      );
      await outbox.enqueue(_pendingVote('resolution-nobody-may-read'));
      await test.database.close();

      final bytes = test.file!.readAsBytesSync();

      expect(
        String.fromCharCodes(bytes),
        isNot(contains('resolution-nobody-may-read')),
      );
      expect(
        String.fromCharCodes(bytes.take(15)),
        isNot(equals('SQLite format 3')),
      );
    });
  });

  Future<
    ({TestDatabase test, FakeMonitoring monitoring, DriftVoteOutbox outbox})
  >
  openOutbox() async {
    final test = await openTestDatabase();
    final monitoring = FakeMonitoring();
    final outbox = DriftVoteOutbox(
      database: test.database,
      monitoring: monitoring,
    );
    return (test: test, monitoring: monitoring, outbox: outbox);
  }

  group('DriftVoteOutbox, on the rows it keeps', () {
    test('holds a vote in columns, the choice and the status among them, '
        'in the order of enqueueing', () async {
      final (:test, monitoring: _, :outbox) = await openOutbox();
      final first = _pendingVote('r1', at(900));
      await outbox.enqueue(first);
      await outbox.enqueue(_pendingVote('r2', at(100)));
      await outbox.markAttempt(first.vote.idempotencyKey);

      final rows = await _rows(test);

      expect(rows, hasLength(2));
      expect(
        rows.first,
        equals({
          'sequence': 1,
          'idempotency_key': first.vote.idempotencyKey,
          'voter_id': 'voter-1',
          'resolution_id': 'r1',
          'meeting_id': first.vote.meetingId,
          'choice': first.vote.choice.value,
          'cast_at': first.vote.castAt,
          'enqueued_at': at(900),
          'attempts': 1,
          'status': OutboxStatus.pending.value,
          'rejection_reason': null,
          'rejected_at': null,
        }),
      );
      expect(rows.last['sequence'], equals(2));
      expect(rows.last['resolution_id'], equals('r2'));
      expect(rows.last['attempts'], equals(0));
    });

    test('writes the reason and the instant of a rejection '
        'with the status, in the same row', () async {
      final (:test, monitoring: _, :outbox) = await openOutbox();
      final queued = _pendingVote('r1');
      await outbox.enqueue(queued);

      await outbox.reject(
        queued.vote.idempotencyKey,
        voteUndeliverable(5),
        at(77),
      );

      final rows = await _rows(test);
      expect(rows, hasLength(1));
      expect(rows.single['status'], equals(OutboxStatus.rejected.value));
      expect(
        rows.single['rejection_reason'],
        equals('{"code":"voteUndeliverable","attempts":5}'),
      );
      expect(rows.single['rejected_at'], equals(at(77)));
    });

    test('never gives a number back: a vote enqueued after one was removed '
        'has a number of its own', () async {
      final (:test, monitoring: _, :outbox) = await openOutbox();
      final first = _pendingVote('r1');
      await outbox.enqueue(first);
      await outbox.remove(first.vote.idempotencyKey);

      await outbox.enqueue(first);

      expect([for (final row in await _rows(test)) row['sequence']], [2]);
    });

    final refused = <(String, String)>[
      (
        'a pending vote with a reason',
        "UPDATE $_votes SET $_reasonColumn = '{}'",
      ),
      (
        'a rejected vote without a reason',
        "UPDATE $_votes SET $_statusColumn = 'rejected'",
      ),
      (
        'a pending vote with an instant of rejection',
        'UPDATE $_votes SET $_rejectedAtColumn = 5',
      ),
      (
        'a rejected vote with a reason and no instant',
        "UPDATE $_votes SET $_statusColumn = 'rejected', "
            "$_reasonColumn = '{}'",
      ),
      (
        'a rejected vote with an instant and no reason',
        "UPDATE $_votes SET $_statusColumn = 'rejected', "
            '$_rejectedAtColumn = 5',
      ),
      (
        'a status that is neither',
        "UPDATE $_votes SET $_statusColumn = 'sent'",
      ),
      ('an empty status', "UPDATE $_votes SET $_statusColumn = ''"),
      ('no status', 'UPDATE $_votes SET $_statusColumn = NULL'),
      ('no key', 'UPDATE $_votes SET $_keyColumn = NULL'),
      ('no voter', 'UPDATE $_votes SET $_voterColumn = NULL'),
      ('no attempts', 'UPDATE $_votes SET $_attemptsColumn = NULL'),
      (
        'a second row with the same key',
        'INSERT INTO $_votes SELECT $_sequenceColumn + 100, $_keyColumn, '
            '$_voterColumn, $_resolutionColumn, $_meetingColumn, '
            '$_choiceColumn, $_castAtColumn, $_enqueuedAtColumn, '
            '$_attemptsColumn, $_statusColumn, $_reasonColumn, '
            '$_rejectedAtColumn FROM $_votes',
      ),
    ];
    for (final (name, statement) in refused) {
      test('is refused by the database: $name', () async {
        final (:test, monitoring: _, :outbox) = await openOutbox();
        await outbox.enqueue(_pendingVote('r1'));

        await expectLater(
          test.database.run(statement),
          throwsA(isA<SqliteException>()),
        );
      });
    }
  });

  group('DriftVoteOutbox, on rows that no longer read back', () {
    /// Changes a column of the vote of r1, behind the back of the outbox.
    Future<
      ({
        TestDatabase test,
        FakeMonitoring monitoring,
        DriftVoteOutbox outbox,
        PendingVote queued,
        Map<String, Object?>? corrupted,
      })
    >
    corruptWith(String column, Object? value) async {
      final (:test, :monitoring, :outbox) = await openOutbox();
      final queued = _pendingVote('r1');
      await outbox.enqueue(queued);
      await outbox.enqueue(_pendingVote('r2'));
      await test.database.run(
        'UPDATE $_votes SET $column = ? '
        "WHERE $_resolutionColumn = 'r1'",
        [value],
      );
      final corrupted = (await _rows(test))
          .where((row) => row['resolution_id'] == 'r1')
          .firstOrNull;
      return (
        test: test,
        monitoring: monitoring,
        outbox: outbox,
        queued: queued,
        corrupted: corrupted,
      );
    }

    final corruptions = <(String, String, Object)>[
      ('a choice that is not one', _choiceColumn, 'maybe'),
      ('an instant that is not one', _enqueuedAtColumn, -4),
      ('an attempt count that is not whole', _attemptsColumn, 1.5),
      ('a key that is not the key of the vote', _keyColumn, 'another-key'),
    ];
    for (final (name, column, value) in corruptions) {
      group('a vote with $name', () {
        test('is left out of the votes, counted, and reported', () async {
          final (test: _, :monitoring, :outbox, queued: _, corrupted: _) =
              await corruptWith(column, value);

          final listed = await outbox.list(_voter);

          expect(
            valueOfListing(listed).votes
                .map((entry) => entry.vote.resolutionId),
            equals([aResolutionId('r2')]),
          );
          expect(valueOfListing(listed).unreadable, equals(1));
          expect(
            monitoring.capturedEvents(),
            equals([MonitoringEvent.storedRowQuarantined]),
          );
        });

        test('is kept as it is, with its status the only thing '
            'that changed', () async {
          final (:test, monitoring: _, :outbox, queued: _, :corrupted) =
              await corruptWith(column, value);

          await outbox.list(_voter);

          final rows = await _rows(test);
          final kept = rows.firstWhere((row) => row['resolution_id'] == 'r1');
          expect(rows, hasLength(2));
          expect(kept, equals({...corrupted!, 'status': outboxQuarantined}));
        });

        test('is reported once: the next read finds it quarantined '
            'and says nothing', () async {
          final (test: _, :monitoring, :outbox, queued: _, corrupted: _) =
              await corruptWith(column, value);

          await outbox.list(_voter);
          final again = await outbox.list(_voter);

          expect(valueOfListing(again).unreadable, equals(1));
          expect(
            monitoring.capturedEvents(),
            equals([MonitoringEvent.storedRowQuarantined]),
          );
        });
      });
    }

    final reasons = <(String, String)>[
      ('text that is not JSON', 'not json'),
      ('a reason of a kind nobody knows', '{"code":"somethingElse"}'),
      ('a reason without its fields', '{"code":"alreadyVoted"}'),
    ];
    for (final (name, reason) in reasons) {
      test('keeps a rejected vote whose reason is $name, '
          'out of the votes', () async {
        final (:test, :monitoring, :outbox) = await openOutbox();
        final queued = _pendingVote('r1');
        await outbox.enqueue(queued);
        await outbox.reject(
          queued.vote.idempotencyKey,
          const ResolutionClosedError(),
          at(5),
        );
        await test.database.run('UPDATE $_votes SET $_reasonColumn = ?', [
          reason,
        ]);

        final listed = await outbox.list(_voter);

        expect(
          listed,
          equals(ok(const OutboxListing(votes: <OutboxVote>[], unreadable: 1))),
        );
        expect(
          monitoring.capturedEvents(),
          equals([MonitoringEvent.storedRowQuarantined]),
        );
        final rows = await _rows(test);
        expect(rows.single['status'], equals(outboxQuarantined));
        expect(rows.single['rejection_reason'], equals(reason));
      });
    }

    test('reports a row without anything that identifies the vote, '
        'the voter or the choice', () async {
      final (test: _, :monitoring, :outbox, queued: _, corrupted: _) =
          await corruptWith(_choiceColumn, 'maybe');

      await outbox.list(_voter);

      expect(
        '${monitoring.errors}',
        isNot(matches(RegExp('maybe|voter-1|resolution|meeting-1'))),
      );
      expect(monitoring.errors.map((captured) => captured.attributes), [
        {LogAttribute.resource: 'outboxVote'},
      ]);
    });

    test('does not overwrite a row that holds the key of a vote '
        'but is no vote: the vote is refused, the row kept', () async {
      final (:test, :monitoring, :outbox, :queued, :corrupted) =
          await corruptWith(_choiceColumn, 'maybe');

      final again = await outbox.enqueue(queued);

      expect(again, equals(ok(const EnqueueResult.heldByUnreadable())));
      final rows = await _rows(test);
      expect(rows, hasLength(2));
      expect(
        rows.firstWhere((row) => row['resolution_id'] == 'r1'),
        equals({...corrupted!, 'status': outboxQuarantined}),
      );
      expect(
        monitoring.capturedEvents(),
        equals([MonitoringEvent.storedRowQuarantined]),
      );
      expect(
        await outbox.findByResolution(aResolutionId('r1'), _voter),
        equals(ok(<OutboxVote>[])),
      );
    });

    test('still answers when the row cannot be marked: '
        'it is left out and counted all the same', () async {
      final (:test, monitoring: _, :outbox, queued: _, corrupted: _) =
          await corruptWith(_choiceColumn, 'maybe');
      test.faults.failWhileMatching(RegExp('^UPDATE'));

      final listed = await outbox.list(_voter);

      expect(valueOfListing(listed).votes, hasLength(1));
      expect(valueOfListing(listed).unreadable, equals(1));
      expect(await _rows(test), hasLength(2));
    });

    test('is deleted by a discard that asks for it, '
        'whether or not a read had marked it', () async {
      final (:test, :monitoring, :outbox, queued: _, corrupted: _) =
          await corruptWith(_choiceColumn, 'maybe');

      final discarded = await outbox.discardUnreadable(_voter);

      expect(discarded, equals(ok(1)));
      expect(
        [for (final row in await _rows(test)) row['resolution_id']],
        ['r2'],
      );
      expect(monitoring.errors, isEmpty);
    });

    test('is not deleted by the removal of the key it sits under', () async {
      final (:test, monitoring: _, :outbox, :queued, corrupted: _) =
          await corruptWith(_choiceColumn, 'maybe');
      await outbox.list(_voter);

      await outbox.remove(queued.vote.idempotencyKey);

      expect(await _rows(test), hasLength(2));
    });

    test('is attributed by the voter column, '
        'whatever else the row holds', () async {
      final (:test, monitoring: _, :outbox, queued: _, corrupted: _) =
          await corruptWith(_choiceColumn, 'maybe');

      final other = await outbox.list(aUserId('voter-2'));

      expect(
        other,
        equals(ok(const OutboxListing(votes: <OutboxVote>[], unreadable: 0))),
      );
      expect(await test.database.all('SELECT count(*) AS total FROM $_votes'), [
        {'total': 2},
      ]);
    });
  });

  group('DriftVoteOutbox, after the migration '
      'that makes room for quarantined rows', () {
    final before = schema.migrations.sublist(0, 2);

    test('keeps the votes of a database at version 2, their numbers, '
        'and the next number to give', () async {
      final old = await openTestDatabase(directory, before);
      final oldOutbox = DriftVoteOutbox(
        database: old.database,
        monitoring: FakeMonitoring(),
      );
      final first = _pendingVote('r1', at(1));
      final second = _pendingVote('r2', at(2));
      final third = _pendingVote('r3', at(3));
      for (final queued in [first, second, third]) {
        await oldOutbox.enqueue(queued);
      }
      await oldOutbox.reject(
        second.vote.idempotencyKey,
        voteUndeliverable(5),
        at(9),
      );
      await oldOutbox.remove(third.vote.idempotencyKey);

      final migrated = await old.reopen(schema.migrations);
      final outbox = DriftVoteOutbox(
        database: migrated.database,
        monitoring: FakeMonitoring(),
      );
      final next = _pendingVote('r4', at(4));
      await outbox.enqueue(next);

      expect(
        await outbox.list(_voter),
        equals(
          ok(
            OutboxListing(
              votes: [
                first,
                rejectVote(second, voteUndeliverable(5), at(9)),
                next,
              ],
              unreadable: 0,
            ),
          ),
        ),
      );
      // The number of the vote that was removed is not given again.
      expect(
        [for (final row in await _rows(migrated)) row['sequence']],
        [1, 2, 4],
      );
    });

    test('keeps the index that finds the votes on a resolution', () async {
      final test = await openTestDatabase(directory);

      final indexes = await test.database.all(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND tbl_name = '$_votes'",
      );

      expect([
        for (final row in indexes) row['name'],
      ], contains(StoredIndex.outboxByResolution.value));
    });

    test('leaves no table behind that the migration used', () async {
      final test = await openTestDatabase(directory);

      final tables = await test.database.all(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );

      expect([
        for (final row in tables) row['name'],
      ], isNot(contains(StoredTable.outboxVotesRebuilt.value)));
    });

    final accepted = <(String, String)>[
      (
        'a quarantined row with nothing in it that a vote has',
        'INSERT INTO $_votes ($_keyColumn, $_voterColumn, $_resolutionColumn, '
            '$_meetingColumn, $_choiceColumn, $_castAtColumn, '
            '$_enqueuedAtColumn, $_attemptsColumn, $_statusColumn) '
            "VALUES ('k', 'v', 'r', 'm', 'maybe', 'yesterday', 'x', 'many', "
            "'quarantined')",
      ),
      (
        'a quarantined row with a reason and an instant',
        'INSERT INTO $_votes ($_keyColumn, $_voterColumn, $_resolutionColumn, '
            '$_meetingColumn, $_choiceColumn, $_castAtColumn, '
            '$_enqueuedAtColumn, $_attemptsColumn, $_statusColumn, '
            '$_reasonColumn, $_rejectedAtColumn) '
            "VALUES ('k', 'v', 'r', 'm', 'for', 1, 1, 0, 'quarantined', "
            "'{}', 5)",
      ),
    ];
    for (final (name, statement) in accepted) {
      test('accepts $name', () async {
        final test = await openTestDatabase(directory);

        await expectLater(test.database.run(statement), completes);
      });
    }
  });

  group('DriftVoteOutbox, on a storage that does not answer', () {
    test('turns every call into a storage error '
        'within the time it was given', () async {
      final test = await openTestDatabase();
      final outbox = DriftVoteOutbox(
        database: test.database,
        monitoring: FakeMonitoring(),
        timeoutMillis: 20,
      );
      final queued = _pendingVote('r1');
      test.faults.hang(true);

      final answers = await Future.wait<Result<Object?, AppError>>([
        outbox.enqueue(queued),
        outbox.list(_voter),
        outbox.discardUnreadable(_voter),
        outbox.findByResolution(aResolutionId('r1'), _voter),
        outbox.markAttempt(queued.vote.idempotencyKey),
        outbox.reject(
          queued.vote.idempotencyKey,
          const ResolutionClosedError(),
          at(1),
        ),
        outbox.remove(queued.vote.idempotencyKey),
      ]);

      expect([
        for (final answer in answers)
          switch (answer) {
            Err(:final error) => (error as dynamic).cause,
            Ok() => null,
          },
      ], equals(List.filled(7, 'timeout')));
    });
  });
}

/// What a successful listing holds.
OutboxListing valueOfListing(
  Result<OutboxListing, StorageReadFailedError> result,
) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => throw StateError('Expected a listing, got $error'),
};
