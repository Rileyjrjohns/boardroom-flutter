import 'package:boardroom/domain/shared/result.dart';
import 'package:test/test.dart';

final Result<int, String> success = ok(2);
final Result<int, String> failure = err('boom');

void main() {
  group('Result', () {
    test('builds a success and a failure', () {
      expect(
        ok(1),
        isA<Ok<int, Never>>().having((result) => result.value, 'value', 1),
      );
      expect(
        err('e'),
        isA<Err<Never, String>>().having(
          (result) => result.error,
          'error',
          'e',
        ),
      );
      expect(ok(1), equals(ok(1)));
      expect(err('e'), equals(err('e')));
      expect(ok(1), isNot(equals(err(1))));
    });

    test('tells a success from a failure with the type guards', () {
      expect(isOk(success), isTrue);
      expect(isOk(failure), isFalse);
      expect(isErr(failure), isTrue);
      expect(isErr(success), isFalse);
      expect([success, failure].where(isOk).toList(), equals([success]));
    });

    test('tells a failure from a success '
        'even when the value or the error is undefined', () {
      expect(isErr(err<Object?>(null)), isTrue);
      expect(isOk(err<Object?>(null)), isFalse);
      expect(isOk(ok<Object?>(null)), isTrue);
      expect(isErr(ok<Object?>(null)), isFalse);
    });

    group('map', () {
      test('transforms the value of a success', () {
        expect(map(success, (value) => value * 10), equals(ok(20)));
      });

      test(
        'leaves a failure untouched and does not call the transformation',
        () {
          var calls = 0;
          int transform(int value) {
            calls += 1;
            return value;
          }

          expect(map(failure, transform), same(failure));
          expect(calls, equals(0));
        },
      );
    });

    group('andThen', () {
      test('runs the next step on a success and returns its result', () {
        expect(andThen(success, (value) => ok<int>(value + 1)), equals(ok(3)));
        expect(
          andThen<int, int, String>(success, (_) => err('later')),
          equals(err('later')),
        );
      });

      test('short-circuits on a failure', () {
        var calls = 0;
        Result<int, String> next(int _) {
          calls += 1;
          return ok(0);
        }

        expect(andThen(failure, next), same(failure));
        expect(calls, equals(0));
      });
    });

    group('andThenAsync', () {
      test(
        'runs the next step on a success, given directly or as a promise',
        () async {
          Future<Result<int, String>> next(int value) async => ok(value + 1);

          await expectLater(andThenAsync(success, next), completion(ok(3)));
          await expectLater(
            andThenAsync(Future.value(success), next),
            completion(ok(3)),
          );
        },
      );

      test('returns the failure of the next step', () async {
        await expectLater(
          andThenAsync<int, int, String>(success, (_) async => err('later')),
          completion(err('later')),
        );
      });

      test('short-circuits on a failure', () async {
        var calls = 0;
        Future<Result<int, String>> next(int _) async {
          calls += 1;
          return ok(0);
        }

        await expectLater(
          andThenAsync(Future.value(failure), next),
          completion(same(failure)),
        );
        expect(calls, equals(0));
      });
    });
  });
}
