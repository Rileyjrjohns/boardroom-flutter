import 'package:boardroom/core/infrastructure/shared/sha256.dart';
import 'package:test/test.dart';

// The digest is checked against the published digests of SHA-256 and against
// the ones another implementation (the `sha256sum` of the system, through
// Python's hashlib) gives, on texts that sit on both sides of the boundaries of
// the algorithm (the padding changes at 55, 56, 63 and 64 bytes) and on texts
// that are not ASCII.

final RegExp _digest = RegExp(r'^[0-9a-f]{64}$');

void main() {
  group('sha256Hex', () {
    for (final (name, text, digest) in [
      (
        'nothing',
        '',
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      ),
      (
        'abc',
        'abc',
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      ),
    ]) {
      test('gives the published digest of $name', () {
        expect(sha256Hex(text), equals(digest));
      });
    }

    for (final (length, digest) in [
      (54, 'a3f01b6939256127582ac8ae9fb47a382a244680806a3f613a118851c1ca1d47'),
      (55, '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318'),
      (56, 'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a'),
      (57, 'f13b2d724659eb3bf47f2dd6af1accc87b81f09f59f2b75e5c0bed6589dfe8c6'),
      (63, '7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34'),
      (64, 'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb'),
      (65, '635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0'),
      (119, '31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb'),
      (120, '2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c'),
      (128, '6836cf13bac400e9105071cd6af47084dfacad4e5e302c94bfed24e013afb73e'),
      (
        1000,
        '41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3',
      ),
    ]) {
      test('gives the digest Node gives for $length characters', () {
        expect(sha256Hex('a' * length), equals(digest));
      });
    }

    for (final (name, text, digest) in [
      (
        'accents',
        'Rémunération du comité',
        '970f623bd56901f51a8a5d3da5b74f36dff75fc6d6f49dfb3e1803af754a4f18',
      ),
      (
        'an emoji, which is a surrogate pair',
        'Board \u{1F3DB} pack',
        '2065804402bdf4587de37a349c0d0d920acbe2eb25db8923dfa167fecb760ddf',
      ),
      (
        'characters of three bytes',
        '€ ’ 中文',
        'b27dd71c9c38cde3859c7ce21b34a0b151af2be740d87ca5ec7f97bd506a0323',
      ),
      (
        'separators and quotes',
        '["a|b","c/d",\'e\\\\f\']',
        '89100974744f9fd3d962725053483f3a02765b3618872b0224f91af7a3623832',
      ),
    ]) {
      test('gives the digest Node gives for $name', () {
        expect(sha256Hex(text), equals(digest));
      });
    }

    test('reads a lone surrogate as the replacement character, '
        'as the encoder of Node does', () {
      expect(
        sha256Hex('a\ud800b'),
        equals(
          '05087813392efc16fe8ff448920c6328e53af865df39419436659d9ffda90f7b',
        ),
      );
      expect(sha256Hex('a\ud800b'), equals(sha256Hex('a�b')));
    });

    test('gives 64 lower case hexadecimal digits, '
        'and another digest for another text', () {
      expect(sha256Hex('one'), matches(_digest));
      expect(sha256Hex('one'), isNot(equals(sha256Hex('One'))));
    });
  });
}
