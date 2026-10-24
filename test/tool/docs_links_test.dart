import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/spec_markdown.dart';

// The links of the documents: README.md and every Markdown file of docs/ except
// docs/spec, which is a verbatim copy of the specification of the React Native
// repository (its links point to that repository's tree and are not ours to
// fix). Every relative link must point to a file or a folder that exists and,
// when it has a fragment, to a heading of a Markdown file that has that anchor.
// The pictures of docs/media are made after the text: they are left out of the
// first check and verified apart, which is skipped while the folder is absent.

final String _root = Directory.current.path;
final String _docs = p.join(_root, 'docs');
final String _media = p.join(_docs, 'media');
final String _spec = p.join(_docs, 'spec');

/// Whether [file] is in [directory] or below it.
bool _isIn(String file, String directory) =>
    p.isWithin(directory, file) || p.equals(directory, file);

/// The Markdown files below [directory], as absolute paths, in name order.
List<String> _markdownFilesBelow(String directory) =>
    Directory(directory)
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => path.endsWith('.md'))
        .where((path) => !_isIn(path, _spec))
        .toList()
      ..sort();

final List<String> _documents = [
  p.join(_root, 'README.md'),
  ..._markdownFilesBelow(_docs),
];

bool _isExternal(String target) =>
    RegExp('^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(target);

String _decode(String text) {
  try {
    return Uri.decodeComponent(text);
  } on FormatException {
    return text;
  }
}

/// Where a relative link of [document] points on disk, and its fragment.
({String file, String? fragment}) _resolve(String document, String target) {
  final hash = target.indexOf('#');
  final filePart = hash == -1 ? target : target.substring(0, hash);
  final fragment = hash == -1 ? null : target.substring(hash + 1);
  final file = filePart.isEmpty
      ? document
      : p.normalize(p.join(p.dirname(document), _decode(filePart)));
  return (file: file, fragment: fragment);
}

/// The anchors of a document, as GitHub numbers them when two headings have
/// the same slug (`slug`, `slug-1`, `slug-2`).
Set<String> _anchorsOf(SpecDocument document) {
  final seen = <String, int>{};
  final anchors = <String>{};
  for (final heading in document.headings) {
    final count = seen[heading.slug] ?? 0;
    seen[heading.slug] = count + 1;
    anchors.add(count == 0 ? heading.slug : '${heading.slug}-$count');
  }
  return anchors;
}

final Map<String, Set<String>> _anchorCache = {};

Set<String> _anchorsInFile(String file) =>
    _anchorCache.putIfAbsent(file, () => _anchorsOf(readSpecFile(file)));

/// The problems of the relative links of [document], one line each.
List<String> _problemsOf(String document, {bool Function(String)? skip}) {
  final problems = <String>[];
  for (final link in readSpecFile(document).links) {
    if (_isExternal(link.target)) {
      continue;
    }
    final (:file, :fragment) = _resolve(document, link.target);
    if (skip != null && skip(file)) {
      continue;
    }
    final where =
        '${p.relative(document, from: _root)}:${link.line} '
        '${link.target}';
    if (FileSystemEntity.typeSync(file) == FileSystemEntityType.notFound) {
      problems.add('$where: the file does not exist');
      continue;
    }
    if (fragment == null || fragment.isEmpty) {
      continue;
    }
    if (!FileSystemEntity.isFileSync(file) || !file.endsWith('.md')) {
      problems.add('$where: a fragment needs a Markdown file');
      continue;
    }
    if (!_anchorsInFile(file).contains(fragment)) {
      problems.add('$where: no heading has the anchor #$fragment');
    }
  }
  return problems;
}

/// Every link of the documents that points into docs/media.
List<({String document, int line, String file})> _mediaLinks() => [
  for (final document in _documents)
    for (final link in readSpecFile(document).links)
      if (!_isExternal(link.target) &&
          _isIn(_resolve(document, link.target).file, _media))
        (
          document: p.relative(document, from: _root),
          line: link.line,
          file: _resolve(document, link.target).file,
        ),
];

void main() {
  group('the links of the documents', () {
    for (final document in _documents) {
      test('${p.relative(document, from: _root)} only links to files and '
          'headings that exist', () {
        expect(
          _problemsOf(document, skip: (file) => _isIn(file, _media)),
          isEmpty,
        );
      });
    }

    test(
      'cover the README, the index, the records and the other documents',
      () {
        final relative = _documents
            .map(
              (file) => p.posix.joinAll(p.split(p.relative(file, from: _root))),
            )
            .toList();

        expect(
          relative,
          containsAll([
            'README.md',
            'docs/README.md',
            'docs/adr/README.md',
            'docs/api.md',
            'docs/parity/open-questions.md',
          ]),
        );
        expect(relative.any((file) => file.startsWith('docs/spec/')), isFalse);
      },
    );

    test('are all reachable from the index of docs/', () {
      final index = readSpecFile(p.join(_docs, 'README.md'));
      final linked = {
        for (final link in index.links) link.target.split('#').first,
      };

      final orphans = [
        for (final file in _markdownFilesBelow(_docs))
          if (!p.equals(file, p.join(_docs, 'README.md')) &&
              !p.isWithin(p.join(_docs, 'adr'), file) &&
              !linked.contains(
                p.posix.joinAll(p.split(p.relative(file, from: _docs))),
              ))
            p.relative(file, from: _root),
      ];

      expect(orphans, isEmpty);
    });

    test('list every decision record in the index of the records', () {
      final index = readSpecFile(p.join(_docs, 'adr', 'README.md'));
      final linked = {for (final link in index.links) link.target};

      final unlisted = [
        for (final file in Directory(p.join(_docs, 'adr')).listSync())
          if (file is File &&
              RegExp(r'^\d{4}-').hasMatch(p.basename(file.path)) &&
              !linked.contains(p.basename(file.path)))
            p.basename(file.path),
      ];

      expect(unlisted, isEmpty);
    });
  });

  group('the pictures of docs/media', () {
    // Until the folder exists the check is skipped, not passed, and no
    // placeholder picture is committed.
    test(
      'exist for every link that points to them',
      () {
        final missing = [
          for (final (:document, :line, :file) in _mediaLinks())
            if (!File(file).existsSync())
              '$document:$line ${p.relative(file, from: _root)}',
        ];

        expect(missing, isEmpty);
      },
      skip: Directory(_media).existsSync()
          ? false
          : 'docs/media does not exist yet',
    );

    test('all have a text for the reader', () {
      final withoutAlt = <String>[];
      for (final document in _documents) {
        final lines = File(document).readAsLinesSync();
        for (var index = 0; index < lines.length; index++) {
          for (final match in RegExp(
            r'!\[([^\]]*)\]\(([^)\s]+)\)',
          ).allMatches(lines[index])) {
            if (match.group(1)!.trim().isEmpty) {
              withoutAlt.add(
                '${p.relative(document, from: _root)}:${index + 1}',
              );
            }
          }
        }
      }

      expect(withoutAlt, isEmpty);
    });
  });

  group('the check of the links', () {
    late Directory directory;

    setUpAll(() {
      directory = Directory.systemTemp.createTempSync('boardroom-docs-');
      Directory(p.join(directory.path, 'sub')).createSync();
      File(p.join(directory.path, 'target.md')).writeAsStringSync(
        '# Target\n\n## Same\n\n## Same\n\n## Other `code`\n',
      );
      File(p.join(directory.path, 'sub', 'page.md'))
          .writeAsStringSync('# Page\n');
    });

    tearDownAll(() => directory.deleteSync(recursive: true));

    List<String> check(String text) {
      final file = p.join(directory.path, 'sub', 'doc.md');
      File(file).writeAsStringSync(text);
      return _problemsOf(file)
          .map((problem) => problem.split(' ').skip(1).join(' '))
          .toList();
    }

    test('accepts a file, a folder, a heading and a numbered heading', () {
      expect(
        check(
          '[a](page.md) [b](..) [c](../target.md#target) '
          '[d](../target.md#same-1) [e](../target.md#other-code) '
          '[f](#doc) [g](https://example.com/x#y)\n\n# Doc\n',
        ),
        isEmpty,
      );
    });

    test(
      'refuses a missing file, a missing anchor and a fragment on a folder',
      () {
        final problems = check(
          '[a](nope.md) [b](../target.md#absent) [c](..#x) [d](#nowhere)\n',
        );

        expect(problems, hasLength(4));
        expect(problems[0], contains('the file does not exist'));
        expect(problems[1], contains('no heading has the anchor #absent'));
        expect(problems[2], contains('a fragment needs a Markdown file'));
        expect(problems[3], contains('no heading has the anchor #nowhere'));
      },
    );

    test('does not read a link inside code', () {
      expect(check('`[a](nope.md)`\n\n```\n[b](nope.md)\n```\n'), isEmpty);
    });
  });
}
