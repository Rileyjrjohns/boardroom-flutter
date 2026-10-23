import 'dart:async';
import 'dart:io';

import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/infrastructure/shared/attempt.dart';
import 'package:fake_async/fake_async.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';

const int _soon = 20;
const int _longAfter = 5000;

void main() {
  group('attempt', () {
    test('gives the value of work that succeeds', () async {
      expect(await attempt(() async => 42, _longAfter), equals(ok(42)));
    });

    test('gives a failure for work that rejects, with a cause that '
        'holds no message', () async {
      final result = await attempt<int>(
        () => Future.error(StateError('secret path /tmp/x')),
        _longAfter,
      );

      expect(
        result,
        equals(
          err(
            const AttemptFailure(
              kind: AttemptFailureKind.failed,
              cause: 'unknown failure',
            ),
          ),
        ),
      );
    });

    test(
      'gives a failure for work that throws before it returns a promise',
      () async {
        final result = await attempt<int>(
          () => throw StateError('boom'),
          _longAfter,
        );

        expect(
          result,
          isA<Err<int, AttemptFailure>>().having(
            (failure) => failure.error.kind,
            'kind',
            AttemptFailureKind.failed,
          ),
        );
      },
    );

    test('times out on work that never settles, and ignores what it '
        'does afterwards', () async {
      final hanging = Completer<int>();

      final result = await attempt(() => hanging.future, _soon);
      hanging.completeError(StateError('too late'));
      // The late failure goes nowhere: nothing is left unhandled.
      await Future<void>.delayed(Duration.zero);

      expect(
        result,
        equals(
          err(
            const AttemptFailure(
              kind: AttemptFailureKind.timedOut,
              cause: 'timeout',
            ),
          ),
        ),
      );
    });

    test('does not leave its timer running when the work is done', () {
      fakeAsync((async) {
        unawaited(attempt(() async => 1, _longAfter));
        async.flushMicrotasks();

        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('describeFailure', () {
    test('names the SQLite error code of a database failure', () {
      expect(
        describeFailure(
          SqliteException(
            extendedResultCode: 13,
            message: 'database or disk is full: /secret/path',
          ),
        ),
        equals('sqlite error 13'),
      );
    });

    test('names the error number of a failure of the file system', () {
      expect(
        describeFailure(
          const FileSystemException(
            'cannot write /secret/path',
            '/secret/path',
            OSError('No space left on device', 28),
          ),
        ),
        equals('os error 28'),
      );
    });

    for (final (name, error) in <(String, Object?)>[
      (
        'a failure of the file system with no code',
        const FileSystemException('/secret/path'),
      ),
      ('an object without a code', Object()),
      ('null', null),
      ('a string', 'boom'),
    ]) {
      test('says nothing specific about $name', () {
        expect(describeFailure(error), equals('unknown failure'));
      });
    }
  });
}
