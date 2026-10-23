import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/shared/results.dart';
import 'package:test/test.dart';

void main() {
  group('collect', () {
    test('gives the values in order when every result is a success', () {
      expect(collect([ok(1), ok(2), ok(3)]), equals(ok([1, 2, 3])));
    });

    test('gives an empty list for no result', () {
      expect(collect<int, String>([]), equals(ok(<int>[])));
    });

    test('gives the first failure', () {
      expect(
        collect<int, String>([ok(1), err('first'), err('second')]),
        equals(err('first')),
      );
    });
  });
}
