import 'package:boardroom/infrastructure/shared/issue_paths.dart';
import 'package:test/test.dart';

void main() {
  group('issuePathsOf', () {
    test(
      'lists the paths of the flaws, sorted, without repeats, and no value',
      () {
        expect(
          issuePathsOf([
            ['list', 2, 'n'],
            ['a'],
            ['list', 0, 'n'],
            ['a'],
          ]),
          equals('a,list.0.n,list.2.n'),
        );
      },
    );

    test(r'says $ for a payload that is wrong as a whole', () {
      expect(issuePathsOf([<Object>[]]), equals(r'$'));
    });

    test('lists at most ten paths', () {
      final wide = [
        for (var number = 0; number < 15; number++) <Object>['f$number'],
      ];

      expect(issuePathsOf(wide).split(','), hasLength(10));
    });
  });
}
