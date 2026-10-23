import 'dart:typed_data';

import 'package:meta/meta.dart';

// A tiny PDF writer, in plain Dart: just enough to give the demo documents a
// content that a real PDF reader opens. One page of A4 for each page of the
// document, showing its title and "page i / n", in the standard fonts that
// every
// reader has (Helvetica), so there is nothing to embed: no font file, no image,
// no compression. It is not a library: it writes the objects of a document that
// has pages of text, and nothing else.
//
// A PDF is a list of numbered objects, a table that says where each one starts
// in the file (`xref`), and a trailer that says where the table starts. Every
// offset is a number of bytes, so the file is built as a string in which one
// character is one byte (Latin-1, which the text encoding below keeps to), and
// converted at the end.

/// The most pages a demo document gets, whatever the document says it has: the
/// metadata of a document may announce thousands of pages, and a demo does not
/// need a file that long. The page indicator of the viewer shows what the file
/// has.
const int demoPdfMaxPages = 100;

/// What a demo PDF is made from.
@immutable
final class DocumentPdfSpec {
  /// Creates the specification of a PDF.
  const new({required this.title, required this.pageCount});

  /// The title of the document, printed on every page.
  final String title;

  /// The number of pages the document says it has; the file has at most
  /// [demoPdfMaxPages].
  final num pageCount;
}

/// A4, in points.
const int _pageWidth = 595;
const int _pageHeight = 842;
const int _margin = 56;

const int _titleFontSize = 20;
const int _titleLeading = 26;
const int _labelFontSize = 14;

/// How many characters of the title fit on a line. Helvetica Bold is about 0.6
/// em wide on average for text, so 36 characters of 20 points take about 430 of
/// the 483 points between the margins.
const int _titleLineCharacters = 36;
const int _titleTop = _pageHeight - _margin - _titleFontSize;
const int _labelBottom = _margin;

const int _firstPageObject = 5;
const int _objectsPerPage = 2;
const int _catalog = 1;
const int _pages = 2;
const int _regularFont = 3;
const int _boldFont = 4;

/// The names the page resources give the two fonts, which the drawing
/// instructions use.
const String _regularFontName = 'F1';
const String _boldFontName = 'F2';

/// The fonts of a page, by the names the drawing instructions use.
const String _resources =
    '/Resources << /Font << /$_regularFontName $_regularFont 0 R '
    '/$_boldFontName $_boldFont 0 R >> >>';

const String _header = '%PDF-1.4\n';

/// Bytes above 127 in the second line tell programs that the file is binary, as
/// the format advises.
const String _binaryMarker = '%âãÏÓ\n';
const int _substitute = 0x3f;
const int _space = 0x20;

/// The code points of the Windows-1252 range 0x80-0x9f that the standard fonts
/// show, and their byte.
const Map<int, int> _winAnsiSpecials = {
  0x20ac: 0x80,
  0x201a: 0x82,
  0x0192: 0x83,
  0x201e: 0x84,
  0x2026: 0x85,
  0x2020: 0x86,
  0x2021: 0x87,
  0x02c6: 0x88,
  0x2030: 0x89,
  0x0160: 0x8a,
  0x2039: 0x8b,
  0x0152: 0x8c,
  0x017d: 0x8e,
  0x2018: 0x91,
  0x2019: 0x92,
  0x201c: 0x93,
  0x201d: 0x94,
  0x2022: 0x95,
  0x2013: 0x96,
  0x2014: 0x97,
  0x02dc: 0x98,
  0x2122: 0x99,
  0x0161: 0x9a,
  0x203a: 0x9b,
  0x0153: 0x9c,
  0x017e: 0x9e,
  0x0178: 0x9f,
};

/// The byte that shows a character in the standard fonts (WinAnsi), or `?` for
/// one they lack.
int _winAnsiByte(int codePoint) {
  if (codePoint < _space) {
    return _space;
  }
  if (codePoint <= 0x7e) {
    return codePoint;
  }
  if (codePoint >= 0xa0 && codePoint <= 0xff) {
    return codePoint;
  }
  return _winAnsiSpecials[codePoint] ?? _substitute;
}

/// A text as a PDF string literal: its characters in WinAnsi, with the three
/// that mean something escaped.
String pdfLiteral(String text) {
  final literal = StringBuffer();
  for (final codePoint in text.runes) {
    final written = String.fromCharCode(_winAnsiByte(codePoint));
    literal.write(
      written == '(' || written == ')' || written == r'\'
          ? '\\$written'
          : written,
    );
  }
  return '($literal)';
}

final RegExp _whiteSpace = RegExp(r'\s+');

/// The title cut into lines of at most [limit] characters, at spaces where it
/// can be and in the middle of a word that is longer than a line. Runs of white
/// space count as one space.
List<String> wrapText(String text, int limit) {
  final lines = <String>[];
  var line = '';
  for (final word in text.split(_whiteSpace).where((part) => part != '')) {
    var rest = word;
    while (rest.length > limit) {
      if (line != '') {
        lines.add(line);
        line = '';
      }
      lines.add(rest.substring(0, limit));
      rest = rest.substring(limit);
    }
    if (line == '') {
      line = rest;
    } else if (line.length + 1 + rest.length <= limit) {
      line = '$line $rest';
    } else {
      lines.add(line);
      line = rest;
    }
  }
  if (line != '') {
    lines.add(line);
  }
  return lines;
}

/// How many pages the file of a document has.
int pdfPageCountOf(num pageCount) {
  if (!pageCount.isFinite) {
    return 1;
  }
  return pageCount.truncate().clamp(1, demoPdfMaxPages);
}

/// The drawing instructions of one page: the title at the top and the page
/// label
/// at the bottom.
String _pageContent(List<String> titleLines, int page, int total) {
  final title = titleLines
      .map((line) => '${pdfLiteral(line)} Tj')
      .join('\nT*\n');
  return [
    'BT',
    '/$_boldFontName $_titleFontSize Tf',
    '$_titleLeading TL',
    '$_margin $_titleTop Td',
    title,
    'ET',
    'BT',
    '/$_regularFontName $_labelFontSize Tf',
    '$_margin $_labelBottom Td',
    '${pdfLiteral('page $page / $total')} Tj',
    'ET',
  ].join('\n');
}

/// A valid PDF for a document: one page of its title and its page label for
/// each of its pages.
Uint8List createDocumentPdf(DocumentPdfSpec spec) {
  final total = pdfPageCountOf(spec.pageCount);
  final titleLines = wrapText(spec.title, _titleLineCharacters);

  final objects = <int, String>{};
  int pageObject(int index) => _firstPageObject + _objectsPerPage * index;

  objects[_catalog] = '<< /Type /Catalog /Pages $_pages 0 R >>';
  objects[_pages] = [
    '<< /Type /Pages',
    '/Kids [${List.generate(total, (index) => '${pageObject(index)} 0 R').join(' ')}]',
    '/Count $total >>',
  ].join(' ');
  objects[_regularFont] =
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>';
  objects[_boldFont] =
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold '
      '/Encoding /WinAnsiEncoding >>';
  for (var index = 0; index < total; index += 1) {
    final content = _pageContent(titleLines, index + 1, total);
    objects[pageObject(index)] = [
      '<< /Type /Page /Parent $_pages 0 R',
      '/MediaBox [0 0 $_pageWidth $_pageHeight]',
      _resources,
      '/Contents ${pageObject(index) + 1} 0 R >>',
    ].join(' ');
    objects[pageObject(index) + 1] =
        '<< /Length ${content.length} >>\nstream\n$content\nendstream';
  }

  final file = StringBuffer('$_header$_binaryMarker');
  final offsets = <int, int>{};
  // The objects are numbered from 1; the free entry 0 of the table comes first.
  final size = objects.length + 1;
  for (var number = 1; number < size; number += 1) {
    offsets[number] = file.length;
    file.write('$number 0 obj\n${objects[number] ?? ''}\nendobj\n');
  }

  // The table: one line of exactly 20 bytes for each object, the free entry 0
  // first.
  final tableOffset = file.length;
  final lines = ['0000000000 65535 f '];
  for (var number = 1; number < size; number += 1) {
    lines.add('${'${offsets[number]}'.padLeft(10, '0')} 00000 n ');
  }
  file
    ..write('xref\n0 $size\n${lines.join('\n')}\n')
    ..write(
      'trailer\n<< /Size $size /Root $_catalog 0 R >>\n'
      'startxref\n$tableOffset\n%%EOF\n',
    );

  return Uint8List.fromList(file.toString().codeUnits);
}
