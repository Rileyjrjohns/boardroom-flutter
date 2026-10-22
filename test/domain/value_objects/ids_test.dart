import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:test/test.dart';

import '../support/names.dart';

typedef _Parser = Result<Object, ValidationError> Function(String raw);

final List<(String, _Parser, ValidationField)> _parsers = [
  ('user id', parseUserId, ValidationField.userId),
  ('meeting id', parseMeetingId, ValidationField.meetingId),
  ('agenda item id', parseAgendaItemId, ValidationField.agendaItemId),
  ('resolution id', parseResolutionId, ValidationField.resolutionId),
  ('document id', parseDocumentId, ValidationField.documentId),
];

void main() {
  for (final (name, parse, field) in _parsers) {
    group('the $name', () {
      test('is kept exactly as received', () {
        expect(parse('a1-B2_c3'), equals(ok('a1-B2_c3')));
        expect(parse(' padded '), equals(ok(' padded ')));
      });

      for (final raw in ['', '   ']) {
        test('rejects the blank id ${formatJson(raw)} and names the field', () {
          expect(
            parse(raw),
            equals(err(validationError(field, ValidationRule.required))),
          );
        });
      }

      for (final (what, raw) in [
        ('a lone high surrogate', '\ud800'),
        ('a lone low surrogate', '\udc00'),
        ('a high surrogate at the end', 'abc\ud83d'),
        ('a low surrogate before its high one', '\ude00\ud83d'),
        ('a high surrogate followed by a letter', '\ud83dx'),
      ]) {
        test('rejects $what: the text cannot be encoded', () {
          expect(
            parse(raw),
            equals(err(validationError(field, ValidationRule.invalidFormat))),
          );
        });
      }

      test('accepts a character outside the basic plane, '
          'written as a pair of surrogates', () {
        expect(parse('a\u{1F600}b'), equals(ok('a\u{1F600}b')));
      });

      for (final raw in ['.', '..']) {
        test(
          'rejects ${formatJson(raw)}, which a path would read as a directory',
          () {
            expect(
              parse(raw),
              equals(err(validationError(field, ValidationRule.invalidFormat))),
            );
          },
        );
      }

      for (final raw in ['...', '.a', 'a.', 'a..b', ' . ']) {
        test('accepts ${formatJson(raw)}, which is not a directory name', () {
          expect(parse(raw), equals(ok(raw)));
        });
      }

      test('accepts 128 characters and rejects 129', () {
        expect(parse('a' * 128), equals(ok('a' * 128)));
        expect(
          parse('a' * 129),
          equals(err(validationError(field, ValidationRule.tooLong))),
        );
      });
    });
  }
}
