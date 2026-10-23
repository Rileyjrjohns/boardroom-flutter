import 'package:boardroom/infrastructure/http/well_formed.dart';
import 'package:test/test.dart';

// Text that can be written in an address. `encodeURIComponent` throws for a
// lone surrogate where `Uri.encodeComponent` writes U+FFFD, so the adapters
// check first. React Native has no test file for it: the JavaScript function
// does it.

const String _highSurrogate = '\uD800';
const String _lowSurrogate = '\uDC00';

void main() {
  group('isWellFormed', () {
    for (final text in [
      '',
      'abc',
      'résolution 1/a',
      '決議1',
      '\u{1F5F3}',
      'a\u{1F464}b',
    ]) {
      test('accepts ${text.codeUnits}', () {
        expect(isWellFormed(text), isTrue);
      });
    }

    for (final (name, text) in [
      ('a lone high surrogate', _highSurrogate),
      ('a lone low surrogate', _lowSurrogate),
      ('a high surrogate at the end', 'ab$_highSurrogate'),
      ('a high surrogate followed by a letter', '${_highSurrogate}b'),
      ('a low surrogate before a high one', '$_lowSurrogate$_highSurrogate'),
    ]) {
      test('refuses $name', () {
        expect(isWellFormed(text), isFalse);
      });
    }
  });

  group('requireWellFormed', () {
    test('gives the text back when it is well formed', () {
      expect(requireWellFormed('a b'), equals('a b'));
    });

    test('throws, and says nothing of the text, when it is not', () {
      expect(
        () => requireWellFormed('secret$_highSurrogate'),
        throwsA(
          isA<IllFormedTextException>()
              .having((e) => e.message, 'message', isNot(contains('secret')))
              .having((e) => '$e', 'toString', isNot(contains('secret'))),
        ),
      );
    });
  });

  group('encodeUriComponent', () {
    test('writes every character the URI standard reserves as an escape', () {
      expect(encodeUriComponent('a b&c=d/é'), equals('a%20b%26c%3Dd%2F%C3%A9'));
    });

    test('leaves the characters encodeURIComponent leaves', () {
      expect(encodeUriComponent("-_.!~*'()"), equals("-_.!~*'()"));
    });

    test('throws for text that is not well formed', () {
      expect(
        () => encodeUriComponent(_lowSurrogate),
        throwsA(isA<IllFormedTextException>()),
      );
    });
  });
}
