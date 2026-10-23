import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/shared/valid.dart';
import 'package:test/test.dart';

void main() {
  group('valid', () {
    test('gives the value of a success', () {
      expect(valid(ok(42)), equals(42));
    });

    test('throws, naming what was wrong, on a failure: '
        'static data that is invalid is a bug', () {
      expect(
        () => valid(err('broken')),
        throwsA(isA<InvalidStaticValueError>()),
      );
      expect(
        () => valid(err('broken')),
        throwsA(
          isA<InvalidStaticValueError>().having(
            (error) => error.toString(),
            'message',
            contains('broken'),
          ),
        ),
      );
    });
  });
}
