import 'package:boardroom/core/domain/shared/validation.dart';
import 'package:test/test.dart';

// Dart only: the React Native domain uses `String.prototype.trim`, which has no
// test of its own there. Dart's `String.trim` removes a slightly different set
// of characters, so the domain trims with trimText; these tests pin the set to
// the one of JavaScript.
void main() {
  group('trimText', () {
    test('removes the white space and the line terminators of JavaScript', () {
      for (final unit in [
        0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x20, 0xa0, 0x1680, 0x2000, 0x200a, //
        0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff,
      ]) {
        final space = String.fromCharCode(unit);

        expect(trimText('$space a b $space'), equals('a b'));
      }
    });

    test(
      'keeps the characters that JavaScript does not take for white space',
      () {
        for (final unit in [0x85, 0x180e, 0x200b]) {
          final mark = String.fromCharCode(unit);

          expect(trimText('${mark}a$mark'), equals('${mark}a$mark'));
        }
      },
    );

    test('keeps the inner white space and trims an empty or blank text', () {
      expect(trimText('  a \t b  '), equals('a \t b'));
      expect(trimText(''), isEmpty);
      expect(trimText(' \n\t '), isEmpty);
    });
  });
}
