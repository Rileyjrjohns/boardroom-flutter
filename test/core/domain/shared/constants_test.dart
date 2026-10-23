import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:test/test.dart';

enum _Colour implements StableValue {
  red('red'),
  green('green');

  new(this.value);

  @override
  final String value;
}

enum _Choice implements StableValue {
  forChoice('for'),
  against('against');

  new(this.value);

  @override
  final String value;
}

void main() {
  group('constants helpers', () {
    test('lists the values of a const object', () {
      expect(valuesOf(_Colour.values), equals(['red', 'green']));
    });

    test('finds the member of a list that equals a raw string', () {
      expect(findConstant(_Colour.values, 'green'), equals(_Colour.green));
    });

    test(
      'does not take a longer string for a member that is only its beginning',
      () {
        const choices = _Choice.values;

        expect(findConstant(choices, 'forward'), isNull);
        expect(findConstant(choices, 'fo'), isNull);
        expect(findConstant(choices, 'againstit'), isNull);
        expect(findConstant(choices, ' for'), isNull);
      },
    );

    test('returns undefined for a raw string that is not a member', () {
      expect(findConstant(_Colour.values, 'blue'), isNull);
      expect(findConstant(_Colour.values, 'Red'), isNull);
    });
  });
}
