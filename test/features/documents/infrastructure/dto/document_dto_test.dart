import 'dart:convert';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/features/documents/infrastructure/dto/document_dto.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';

final Map<String, Object?> _wire = toDocumentWire(aDocument()).toJson();

Result<DocumentWire, WireFailure> _parse(Object? json) =>
    decodeWire(json, DocumentWire.fromJson);

void main() {
  group('the document schema', () {
    test(
      'reads the wire of a document and ignores the fields it does not know',
      () {
        final parsed = _parse({..._wire, 'extra': 1});

        expect(switch (parsed) {
          Ok(:final value) => value.toJson(),
          Err() => null,
        }, equals(_wire));
      },
    );

    for (final field in _wire.keys) {
      test('fails when $field is missing', () {
        final rest = {..._wire}..remove(field);

        expect(_parse(rest), equals(err(WireFailure(field))));
      });
    }

    for (final (field, value) in <(String, Object?)>[
      ('id', 1),
      ('title', null),
      ('confidentiality', 3),
      ('pageCount', '12'),
    ]) {
      test('fails when $field is ${jsonEncode(value)}', () {
        expect(
          _parse({..._wire, field: value}),
          equals(err(WireFailure(field))),
        );
      });
    }

    for (final document in [aDocument(), aConfidentialDocument()]) {
      test('gives a document back as it was', () {
        final parsed = unwrap(
          _parse(jsonDecode(jsonEncode(toDocumentWire(document).toJson()))),
        );

        expect(toDocument(parsed), equals(ok(document)));
      });
    }

    for (final (name, change, field)
        in <(String, Map<String, Object?>, ValidationField)>[
          (
            'a level nobody knows',
            {'confidentiality': 'secret'},
            ValidationField.confidentialityLevel,
          ),
          ('a blank title', {'title': ' '}, ValidationField.title),
          ('a page count of zero', {'pageCount': 0}, ValidationField.pageCount),
          ('a blank id', {'id': ''}, ValidationField.documentId),
        ]) {
      test('refuses $name through the factory of the domain', () {
        final mapped = toDocument(unwrap(_parse({..._wire, ...change})));

        expect(
          mapped,
          isA<Err<Object?, ValidationError>>().having(
            (result) => result.error.field,
            'field',
            field,
          ),
        );
      });
    }
  });
}
