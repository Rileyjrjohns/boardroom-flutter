import 'package:boardroom/domain/shared/result.dart';
import 'package:test/test.dart';

// Dart only: how a Result is compared and printed, and that a switch over it
// is exhaustive (the TypeScript union is narrowed by the compiler in the same
// way, without a test).

String describe(Result<int, String> result) => switch (result) {
  Ok(:final value) => 'ok $value',
  Err(:final error) => 'err $error',
};

void main() {
  group('a Result', () {
    test('compares by value, lists included', () {
      expect(ok([1, 2]), equals(ok([1, 2])));
      expect(ok([1, 2]).hashCode, equals(ok([1, 2]).hashCode));
      expect(err({'a': 1}), equals(err({'a': 1})));
      expect(err({'a': 1}).hashCode, equals(err({'a': 1}).hashCode));
      expect(ok([1, 2]), isNot(equals(ok([2, 1]))));
      expect(ok(1), isNot(equals(err(1))));
      expect(err(1), isNot(equals(ok(1))));
    });

    test('prints its value or its error', () {
      expect(ok(1).toString(), equals('Ok(1)'));
      expect(err('boom').toString(), equals('Err(boom)'));
    });

    test('is matched exhaustively by a switch', () {
      expect(describe(ok(2)), equals('ok 2'));
      expect(describe(err('boom')), equals('err boom'));
    });
  });
}
