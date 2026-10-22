// A reader for the Markdown files of docs/spec, in plain string handling. The
// convention it reads is documented in docs/spec/README.md ("Conformance
// conventions"): a table whose first header cell is one of the kind labels is a
// *checked table*, the first cell of each of its rows holds an identifier in
// backticks, and the *subject* of a table is the first backticked token of the
// nearest preceding heading. Everything else (prose, other tables) is free and
// is not read here.
import 'dart:io';

import 'package:path/path.dart' as p;

/// The kind labels: the first header cell of a checked table.
abstract final class TableKind {
  /// The values of an error code constant.
  static const String code = 'Code';

  /// The values of an enumeration.
  static const String value = 'Value';

  /// A numeric limit.
  static const String limit = 'Limit';

  /// The use cases.
  static const String useCase = 'Use case';

  /// A configuration setting and its default.
  static const String setting = 'Setting';

  /// A fixed number of the application.
  static const String constant = 'Constant';

  /// The ports.
  static const String port = 'Port';

  /// The operations of the port named by the subject.
  static const String operation = 'Operation';

  /// The routes.
  static const String route = 'Route';

  /// The fixed test ids.
  static const String testId = 'Test id';

  /// The test id builders.
  static const String builder = 'Builder';

  /// Every kind label.
  static const List<String> all = [
    code,
    value,
    limit,
    useCase,
    setting,
    constant,
    port,
    operation,
    route,
    testId,
    builder,
  ];
}

/// A heading of a specification file.
final class Heading {
  /// Creates a heading.
  const new({
    required this.level,
    required this.text,
    required this.subject,
    required this.slug,
    required this.line,
  });

  /// The number of `#`.
  final int level;

  /// The text after the `#`.
  final String text;

  /// The first backticked token of the heading, if it has one.
  final String? subject;

  /// The anchor GitHub gives the heading.
  final String slug;

  /// The line of the heading, from 1.
  final int line;
}

/// A Markdown table.
final class SpecTable {
  /// Creates a table.
  const new({
    required this.kind,
    required this.checked,
    required this.header,
    required this.rows,
    required this.subject,
    required this.line,
  });

  /// The first header cell, without backticks.
  final String kind;

  /// Whether [kind] is one of the kind labels.
  final bool checked;

  /// The cells of the header, trimmed.
  final List<String> header;

  /// The cells of each row, trimmed, with `\|` read as `|`.
  final List<List<String>> rows;

  /// The first backticked token of the nearest preceding heading, if there is
  /// one.
  final String? subject;

  /// The line of the header, from 1.
  final int line;

  /// The identifiers (first backticked token of the first cell) of the rows.
  List<String> get identifiers => [
    for (final row in rows) firstCode(row.firstOrNull ?? '') ?? '',
  ];
}

/// A fenced block.
final class Fence {
  /// Creates a fenced block.
  const new({required this.language, required this.body, required this.line});

  /// The word after the three backticks that open the block.
  final String language;

  /// The lines of the block.
  final String body;

  /// The line that opens the block, from 1.
  final int line;
}

/// A Markdown link outside code.
final class Link {
  /// Creates a link.
  const new({required this.target, required this.line});

  /// What is between the parentheses.
  final String target;

  /// The line of the link, from 1.
  final int line;
}

/// A specification file, read.
final class SpecDocument {
  /// Creates a document.
  const new({
    required this.file,
    required this.lines,
    required this.headings,
    required this.tables,
    required this.fences,
    required this.links,
  });

  /// The name of the file.
  final String file;

  /// The lines of the file.
  final List<String> lines;

  /// Every heading.
  final List<Heading> headings;

  /// Every table, checked or not.
  final List<SpecTable> tables;

  /// Every fenced block.
  final List<Fence> fences;

  /// Every link outside code.
  final List<Link> links;

  /// The checked tables of the given kinds, in file order.
  List<SpecTable> tablesOfKind(Iterable<String> kinds) => [
    for (final table in tables)
      if (table.checked && kinds.contains(table.kind)) table,
  ];

  /// The lines of a section: from its heading to the next heading of the same
  /// or a higher level.
  List<String> sectionLines(Heading heading) {
    final end = headings
        .where((other) => other.line > heading.line)
        .where((other) => other.level <= heading.level)
        .firstOrNull;
    return lines.sublist(heading.line, end == null ? null : end.line - 1);
  }
}

final RegExp _headingPattern = RegExp(r'^(#{1,6})\s+(.+?)\s*$');
final RegExp _fencePattern = RegExp(r'^\s*```(.*)$');
final RegExp _tableRowPattern = RegExp(r'^\s*\|');
final RegExp _tableSeparatorPattern = RegExp(
  r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$',
);
final RegExp _codeSpanPattern = RegExp('`([^`]+)`');
final RegExp _linkPattern = RegExp(r'\[[^\]]*\]\(([^)\s]+)\)');

/// The text between the first pair of backticks, or `null` when there is none.
String? firstCode(String text) => _codeSpanPattern.firstMatch(text)?.group(1);

/// Every text between a pair of backticks.
List<String> allCodes(String text) => [
  for (final match in _codeSpanPattern.allMatches(text)) match.group(1)!,
];

/// The anchor GitHub gives a heading: lower case, punctuation removed, each
/// space a hyphen.
String slugOf(String headingText) => headingText
    .replaceAll('`', '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
    .trim()
    .replaceAll(' ', '-');

/// Splits a table row at the `|` that are not escaped, and reads `\|` as `|`.
List<String> splitRow(String line) {
  final cells = <String>[];
  final text = line.trim();
  final current = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (char == r'\' && index + 1 < text.length && text[index + 1] == '|') {
      current.write('|');
      index++;
    } else if (char == '|') {
      cells.add(current.toString());
      current.clear();
    } else {
      current.write(char);
    }
  }
  cells.add(current.toString());
  // The row starts and ends with a bar: the pieces before the first and after
  // the last are empty.
  if (text.startsWith('|')) {
    cells.removeAt(0);
  }
  if (text.endsWith('|') && !text.endsWith(r'\|')) {
    cells.removeLast();
  }
  return [for (final cell in cells) cell.trim()];
}

/// Adds the links of a line, outside code spans, to [links].
void _readLinks(String line, int lineNumber, List<Link> links) {
  for (final match in _linkPattern.allMatches(
    line.replaceAll(RegExp('`[^`]*`'), ''),
  )) {
    links.add(Link(target: match.group(1)!, line: lineNumber));
  }
}

/// Reads a specification file from its [text].
SpecDocument parseSpecText(String file, String text) {
  final lines = text.split('\n');
  final headings = <Heading>[];
  final tables = <SpecTable>[];
  final fences = <Fence>[];
  final links = <Link>[];

  String? fenceLanguage;
  var fenceLine = 0;
  final fenceBody = <String>[];
  String? subject;

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final fenceMatch = _fencePattern.firstMatch(line);
    if (fenceMatch != null) {
      if (fenceLanguage == null) {
        fenceLanguage = fenceMatch.group(1)!.trim();
        fenceLine = index + 1;
      } else {
        fences.add(
          Fence(
            language: fenceLanguage,
            body: fenceBody.join('\n'),
            line: fenceLine,
          ),
        );
        fenceLanguage = null;
        fenceBody.clear();
      }
      continue;
    }
    if (fenceLanguage != null) {
      fenceBody.add(line);
      continue;
    }

    final headingMatch = _headingPattern.firstMatch(line);
    if (headingMatch != null) {
      final headingText = headingMatch.group(2)!;
      subject = firstCode(headingText);
      headings.add(
        Heading(
          level: headingMatch.group(1)!.length,
          text: headingText,
          subject: subject,
          slug: slugOf(headingText),
          line: index + 1,
        ),
      );
      continue;
    }

    _readLinks(line, index + 1, links);

    final nextLine = index + 1 < lines.length ? lines[index + 1] : '';
    if (_tableRowPattern.hasMatch(line) &&
        _tableSeparatorPattern.hasMatch(nextLine)) {
      final header = splitRow(line);
      final rows = <List<String>>[];
      var next = index + 2;
      while (next < lines.length && _tableRowPattern.hasMatch(lines[next])) {
        rows.add(splitRow(lines[next]));
        _readLinks(lines[next], next + 1, links);
        next++;
      }
      final kind = (header.firstOrNull ?? '').replaceAll('`', '');
      tables.add(
        SpecTable(
          kind: kind,
          checked: TableKind.all.contains(kind),
          header: header,
          rows: rows,
          subject: subject,
          line: index + 1,
        ),
      );
      index = next - 1;
    }
  }

  return SpecDocument(
    file: file,
    lines: lines,
    headings: headings,
    tables: tables,
    fences: fences,
    links: links,
  );
}

/// Reads the specification file at [path].
SpecDocument readSpecFile(String path) =>
    parseSpecText(p.basename(path), File(path).readAsStringSync());
