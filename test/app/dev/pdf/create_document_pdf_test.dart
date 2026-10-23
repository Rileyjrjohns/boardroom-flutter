import 'dart:typed_data';

import 'package:boardroom/app/dev/pdf/create_document_pdf.dart';
import 'package:boardroom/features/documents/infrastructure/pdf_signature.dart';
import 'package:test/test.dart';

import '../../../support/builders/names.dart';

// The writer is tested by reading back what it writes, the way a reader does:
// the header, then the end of the file to find the table of offsets, then each
// object where the table says it is, then the pages from the tree that starts
// at the root of the trailer. A reader that cannot find an object where the
// table says is the failure these checks are made to catch.

String _text(Uint8List bytes) => String.fromCharCodes(bytes);

final class _ParsedPdf {
  const new({
    required this.version,
    required this.size,
    required this.root,
    required this.objects,
    required this.pageContents,
  });

  final String version;
  final int size;
  final int root;
  final Map<int, String> objects;
  final List<String> pageContents;
}

/// Reads a file the way a reader would, and fails the test on anything a reader
/// would refuse.
_ParsedPdf _parse(Uint8List bytes) {
  final file = _text(bytes);
  final header = RegExp(r'^%PDF-(\d\.\d)\n').firstMatch(file);
  if (header == null) {
    throw StateError('no header');
  }

  expect(file.endsWith('\n%%EOF\n'), isTrue);
  final start = RegExp(r'startxref\n(\d+)\n%%EOF\n$').firstMatch(file);
  if (start == null) {
    throw StateError('no startxref');
  }
  final tableOffset = int.parse(start[1]!);
  expect(file.substring(tableOffset, tableOffset + 5), equals('xref\n'));

  final table = RegExp(r'^xref\n0 (\d+)\n')
      .firstMatch(file.substring(tableOffset));
  if (table == null) {
    throw StateError('no table');
  }
  final size = int.parse(table[1]!);
  final entriesAt = tableOffset + table[0]!.length;
  final entries = [
    for (var index = 0; index < size; index++)
      file.substring(entriesAt + index * 20, entriesAt + (index + 1) * 20),
  ];
  // Every entry is exactly 20 bytes: ten digits, a space, five digits, a space,
  // n or f, a space, a line feed.
  for (final entry in entries) {
    expect(entry, matches(RegExp(r'^\d{10} \d{5} [nf] \n$')));
  }
  expect(entries[0], equals('0000000000 65535 f \n'));
  expect(
    file.substring(entriesAt + size * 20, entriesAt + size * 20 + 8),
    equals('trailer\n'),
  );

  final trailer = RegExp(
    r'trailer\n<< /Size (\d+) /Root (\d+) 0 R >>\nstartxref',
  ).firstMatch(file);
  if (trailer == null) {
    throw StateError('no trailer');
  }

  final objects = <int, String>{};
  for (final (index, entry) in entries.skip(1).indexed) {
    final number = index + 1;
    final offset = int.parse(entry.substring(0, 10));
    final object = RegExp('^$number 0 obj\\n([\\s\\S]*?)\\nendobj\\n')
        .firstMatch(file.substring(offset));
    if (object == null) {
      throw StateError('object $number is not at $offset');
    }
    objects[number] = object[1] ?? '';
  }

  final catalog = objects[int.parse(trailer[2]!)] ?? '';
  final pagesNumber = int.parse(
    RegExp(r'/Pages (\d+) 0 R').firstMatch(catalog)![1]!,
  );
  final pages = objects[pagesNumber] ?? '';
  final kids = [
    for (final match in RegExp(
      r'(\d+) 0 R',
    ).allMatches(RegExp(r'/Kids \[([^\]]*)\]').firstMatch(pages)?[1] ?? ''))
      int.parse(match[1]!),
  ];
  expect(
    int.parse(RegExp(r'/Count (\d+)').firstMatch(pages)![1]!),
    equals(kids.length),
  );

  final pageContents = [
    for (final kid in kids)
      () {
        final page = objects[kid] ?? '';
        expect(page, contains('/Type /Page '));
        expect(page, contains('/Parent $pagesNumber 0 R'));
        final content =
            objects[int.parse(
              RegExp(r'/Contents (\d+) 0 R').firstMatch(page)![1]!,
            )] ??
            '';
        final stream = RegExp(
          r'^<< /Length (\d+) >>\nstream\n([\s\S]*)\nendstream$',
        ).firstMatch(content);
        if (stream == null) {
          throw StateError('no stream');
        }
        expect(stream[2]!.length, equals(int.parse(stream[1]!)));
        return stream[2]!;
      }(),
  ];

  return _ParsedPdf(
    version: header[1] ?? '',
    size: int.parse(trailer[1]!),
    root: int.parse(trailer[2]!),
    objects: objects,
    pageContents: pageContents,
  );
}

String _char(int code) => String.fromCharCode(code);

void main() {
  group('createDocumentPdf', () {
    test('writes a file that starts like a PDF and ends like one', () {
      final bytes = createDocumentPdf(
        const DocumentPdfSpec(title: 'Financial statements', pageCount: 3),
      );
      final text = _text(bytes);

      expect(hasPdfSignature(bytes), isTrue);
      expect(text.startsWith('%PDF-1.4\n'), isTrue);
      final tableOffset = RegExp(r'startxref\n(\d+)').firstMatch(text)![1];
      expect(text.endsWith('startxref\n$tableOffset\n%%EOF\n'), isTrue);
    });

    test('says in the second line that the file is binary', () {
      final second = _text(
        createDocumentPdf(const DocumentPdfSpec(title: 'A', pageCount: 1)),
      ).split('\n')[1];

      expect(second.startsWith('%'), isTrue);
      expect(second.substring(1).codeUnits.every((unit) => unit > 127), isTrue);
    });

    test('has its table say where each object is, and the trailer '
        'say how many there are and which is the root', () {
      final parsed = _parse(
        createDocumentPdf(
          const DocumentPdfSpec(title: 'Financial statements', pageCount: 3),
        ),
      );

      expect(parsed.size, equals(parsed.objects.length + 1));
      expect(parsed.root, equals(1));
      expect(parsed.objects[1], contains('/Type /Catalog'));
      expect(parsed.version, equals('1.4'));
    });

    test('has one page for each page of the document', () {
      for (final pageCount in [1, 2, 7, 24]) {
        final parsed = _parse(
          createDocumentPdf(
            DocumentPdfSpec(title: 'Annual report', pageCount: pageCount),
          ),
        );

        expect(parsed.pageContents, hasLength(pageCount));
      }
    });

    test('shows the title and "page i / n" on every page', () {
      final parsed = _parse(
        createDocumentPdf(
          const DocumentPdfSpec(title: 'Annual report', pageCount: 4),
        ),
      );

      for (final (index, content) in parsed.pageContents.indexed) {
        expect(content, contains('(Annual report) Tj'));
        expect(content, contains('(page ${index + 1} / 4) Tj'));
      }
    });

    test('uses the standard Helvetica fonts, and embeds nothing', () {
      final file = _text(
        createDocumentPdf(const DocumentPdfSpec(title: 'A', pageCount: 2)),
      );

      expect(file, contains('/BaseFont /Helvetica '));
      expect(file, contains('/BaseFont /Helvetica-Bold '));
      expect(file, isNot(contains('/FontFile')));
      expect(file, isNot(contains('/Subtype /Image')));
      expect(file, isNot(contains('/Filter')));
    });

    test('gives the page count of the document, up to the maximum '
        'of a demo document', () {
      expect(
        _parse(
          createDocumentPdf(
            const DocumentPdfSpec(title: 'A', pageCount: 10000),
          ),
        ).pageContents,
        hasLength(demoPdfMaxPages),
      );
      expect(pdfPageCountOf(demoPdfMaxPages), equals(demoPdfMaxPages));
      expect(pdfPageCountOf(demoPdfMaxPages + 1), equals(demoPdfMaxPages));
    });

    test('labels the pages with the pages the file has, not the '
        'pages the document announces', () {
      final parsed = _parse(
        createDocumentPdf(const DocumentPdfSpec(title: 'A', pageCount: 10000)),
      );

      expect(
        parsed.pageContents.last,
        contains('(page $demoPdfMaxPages / $demoPdfMaxPages) Tj'),
      );
    });

    for (final pageCount in <num>[
      0,
      -3,
      double.nan,
      double.negativeInfinity,
      0.4,
    ]) {
      test('gives a file of one page for ${formatNumber(pageCount)} '
          'pages, so that the file is always valid', () {
        expect(
          _parse(
            createDocumentPdf(
              DocumentPdfSpec(title: 'A', pageCount: pageCount),
            ),
          ).pageContents,
          hasLength(1),
        );
        expect(pdfPageCountOf(pageCount), equals(1));
      });
    }

    test('rounds a fraction of a page down', () {
      expect(pdfPageCountOf(2.9), equals(2));
    });

    test('writes the same bytes for the same document, so that a '
        'version has one content', () {
      final first = createDocumentPdf(
        const DocumentPdfSpec(title: 'Annual report', pageCount: 5),
      );
      final second = createDocumentPdf(
        const DocumentPdfSpec(title: 'Annual report', pageCount: 5),
      );

      expect(first, equals(second));
    });

    test('writes other bytes for another title or another page '
        'count, so that a new version is told apart', () {
      final base = createDocumentPdf(
        const DocumentPdfSpec(title: 'Annual report', pageCount: 5),
      );

      expect(
        createDocumentPdf(
          const DocumentPdfSpec(title: 'Annual reports', pageCount: 5),
        ),
        isNot(equals(base)),
      );
      expect(
        createDocumentPdf(
          const DocumentPdfSpec(title: 'Annual report', pageCount: 6),
        ),
        isNot(equals(base)),
      );
    });

    test('keeps a title with parentheses and a backslash from '
        'breaking the strings of the file', () {
      final parsed = _parse(
        createDocumentPdf(
          const DocumentPdfSpec(title: r'Plan (draft) \ final)', pageCount: 1),
        ),
      );

      expect(
        parsed.pageContents.first,
        contains(r'(Plan \(draft\) \\ final\)) Tj'),
      );
    });

    test('writes the accents of the standard fonts as the one byte '
        'they have, and a character they lack as a question mark', () {
      final parsed = _parse(
        createDocumentPdf(
          const DocumentPdfSpec(
            title: 'Rémunération € 中 \u{1F3DB}',
            pageCount: 1,
          ),
        ),
      );

      expect(
        parsed.pageContents.first,
        contains(
          '(R${_char(0xe9)}mun${_char(0xe9)}ration ${_char(0x80)} ? ?) Tj',
        ),
      );
    });

    test('writes a title that is long on several lines, so that it '
        'stays on the page', () {
      final title =
          'Report of the remuneration committee on the policy for '
              'the financial year ' *
          3;
      final parsed = _parse(
        createDocumentPdf(DocumentPdfSpec(title: title, pageCount: 1)),
      );

      final lines = RegExp(r'\) Tj').allMatches(parsed.pageContents.first);
      expect(lines.length, greaterThan(3));
      expect(parsed.pageContents.first, contains('T*'));
    });

    test('writes a title of the longest length a document can have', () {
      expect(
        () => _parse(
          createDocumentPdf(DocumentPdfSpec(title: 'w' * 300, pageCount: 2)),
        ),
        returnsNormally,
      );
    });
  });

  group('pdfLiteral', () {
    test('escapes the parentheses and the backslash, and only those', () {
      expect(pdfLiteral(r'a(b)c\d'), equals(r'(a\(b\)c\\d)'));
    });

    test('turns a control character into a space, so that a line '
        'break cannot end the string', () {
      expect(pdfLiteral('a\nb\rc\u0000d'), equals('(a b c d)'));
    });

    test('knows the characters of Windows-1252 beyond Latin-1', () {
      expect(
        pdfLiteral('’“”–—…'),
        equals('(${[0x92, 0x93, 0x94, 0x96, 0x97, 0x85].map(_char).join()})'),
      );
    });
  });

  group('wrapText', () {
    test('keeps a short text on one line, with its white space collapsed', () {
      expect(wrapText('  A   short \n title ', 36), equals(['A short title']));
    });

    test('breaks at spaces, never beyond the limit', () {
      final lines = wrapText('one two three four five six seven', 10);

      expect(lines, equals(['one two', 'three four', 'five six', 'seven']));
      expect(lines.every((line) => line.length <= 10), isTrue);
    });

    test('cuts a word that is longer than a line', () {
      expect(
        wrapText('abcdefghijklmnopqrstuvwxyz', 10),
        equals(['abcdefghij', 'klmnopqrst', 'uvwxyz']),
      );
      expect(
        wrapText('short abcdefghijklmnop end', 10),
        equals(['short', 'abcdefghij', 'klmnop end']),
      );
    });

    test('gives no line for a text with nothing in it', () {
      expect(wrapText('   ', 10), isEmpty);
    });
  });

  group('hasPdfSignature, in Dart', () {
    test('tells a PDF from anything else', () {
      expect(hasPdfSignature(Uint8List.fromList('%PDF-1.7'.codeUnits)), isTrue);
      expect(hasPdfSignature(Uint8List.fromList('<html>'.codeUnits)), isFalse);
      expect(hasPdfSignature(Uint8List.fromList('%PDF'.codeUnits)), isFalse);
      expect(hasPdfSignature(Uint8List(0)), isFalse);
    });
  });
}
