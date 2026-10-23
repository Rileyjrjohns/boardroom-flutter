import 'dart:async';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/persistence/guarded.dart';
import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';

import '../../../support/infrastructure/test_database.dart';

// What the adapters run their statements with: work that settles in bounded
// time, whose failure is a storage error with a cause that says what kind of
// failure it was and nothing else. React Native has no test file for it: the
// adapters' tests cover it.

SqliteException _sqliteFailure(int code) => SqliteException(
  extendedResultCode: code,
  message: 'near "SELECT secret FROM vault": syntax error',
  causingStatement: 'SELECT secret FROM vault',
);

void main() {
  group('guardedRead', () {
    test('gives the value of the work', () async {
      expect(await guardedRead(() async => 3, 1000), equals(ok(3)));
    });

    test('turns a failure of the engine into a storage error '
        'whose cause is its result code', () async {
      final failed = await guardedRead<int>(
        () => Future.error(_sqliteFailure(5)),
        1000,
      );

      expect(failed, equals(err(storageReadFailed('sqlite error 5'))));
    });

    test('puts no statement nor message in the cause', () async {
      final failed = await guardedRead<int>(
        () => Future.error(_sqliteFailure(1)),
        1000,
      );

      expect('$failed', isNot(contains('secret')));
    });

    test(
      'turns a failure that carries no code into the unknown failure',
      () async {
        final failed = await guardedRead<int>(
          () => Future.error(StateError('boom')),
          1000,
        );

        expect(failed, equals(err(storageReadFailed('unknown failure'))));
      },
    );

    test('turns work that does not settle in time into a timeout', () async {
      final failed = await guardedRead<int>(() => Completer<int>().future, 20);

      expect(failed, equals(err(storageReadFailed('timeout'))));
    });

    test('reports the failure under the wrapper drift puts on it', () async {
      final failed = await guardedRead<int>(
        () => Future.error(
          DriftWrappedException(
            message: 'a possible cause',
            cause: _sqliteFailure(19),
          ),
        ),
        1000,
      );

      expect(failed, equals(err(storageReadFailed('sqlite error 19'))));
    });
  });

  group('guardedWrite', () {
    test('gives the value of the work', () async {
      expect(await guardedWrite(() async => 'done', 1000), equals(ok('done')));
    });

    test('turns a failure of the engine into a storage error '
        'whose cause is its result code', () async {
      final failed = await guardedWrite<void>(
        () => Future.error(_sqliteFailure(13)),
        1000,
      );

      expect(failed, equals(err(storageWriteFailed('sqlite error 13'))));
    });

    test('turns work that does not settle in time into a timeout', () async {
      final failed = await guardedWrite<void>(
        () => Completer<void>().future,
        20,
      );

      expect(failed, equals(err(storageWriteFailed('timeout'))));
    });

    test('reports the failure that made a transaction roll back, '
        'not the rollback that failed too', () async {
      final test = await openTestDatabase();
      test.faults.failNextRollback();

      final failed = await guardedWrite<void>(
        () => test.database.transaction(() async {
          await test.database.run('INSERT INTO nowhere VALUES (1)');
        }),
        1000,
      );

      expect(failed, equals(err(storageWriteFailed('sqlite error 1'))));
    });
  });

  group('engineFailureOf', () {
    test('is the failure itself when drift wrapped nothing', () {
      final failure = _sqliteFailure(5);

      expect(engineFailureOf(failure), same(failure));
    });

    test('is the cause of a failure drift explained', () {
      final cause = _sqliteFailure(5);

      expect(
        engineFailureOf(DriftWrappedException(message: 'why', cause: cause)),
        same(cause),
      );
    });

    test('is the wrapper itself when it holds no cause', () {
      final wrapper = DriftWrappedException(message: 'why');

      expect(engineFailureOf(wrapper), same(wrapper));
    });

    test('is the failure that made a transaction roll back', () {
      final cause = _sqliteFailure(5);

      expect(
        engineFailureOf(
          CouldNotRollBackException(cause, StackTrace.current, 'rollback'),
        ),
        same(cause),
      );
    });
  });

  test('gives a statement ten seconds by default', () {
    expect(defaultStatementTimeoutMillis, equals(10000));
  });
}
