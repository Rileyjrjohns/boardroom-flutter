// Pure Dart: runs with `dart test test/tool`, without Flutter.

import 'package:test/test.dart';

import '../../tool/coverage_helper.dart';

void main() {
  group('readPackageName', () {
    test('reads the name of the package', () {
      expect(
        readPackageName('name: boardroom\ndescription: "x"\n'),
        'boardroom',
      );
    });

    test('ignores an indented name', () {
      expect(
        () => readPackageName('flutter:\n  name: other\n'),
        throwsFormatException,
      );
    });
  });

  group('isPartFile', () {
    test('recognises a part of another library', () {
      expect(isPartFile("// header\npart of 'a.dart';\n"), isTrue);
      expect(isPartFile('part of a;\n'), isTrue);
    });

    test('lets a library through', () {
      expect(isPartFile("import 'b.dart';\npart 'a.g.dart';\n"), isFalse);
    });
  });

  group('buildCoverageHelper', () {
    test('imports each library once, sorted, and has an empty main', () {
      final source = buildCoverageHelper('boardroom', [
        'lib/app/app.dart',
        'lib/features/meetings/domain/entities/meeting.dart',
      ]);

      expect(
        source,
        contains(
          "import 'package:boardroom/app/app.dart';\n"
          "import 'package:boardroom/features/meetings/domain/entities/meeting.dart';\n",
        ),
      );
      expect(source, contains('void main() {}'));
      expect(
        source,
        contains('\n// ignore_for_file: directives_ordering, unused_import\n'),
      );
    });

    test('writes the same file for the same libraries', () {
      final first = buildCoverageHelper('p', ['lib/b.dart', 'lib/a.dart']);
      final second = buildCoverageHelper('p', ['lib/a.dart', 'lib/b.dart']);

      expect(first, second);
    });
  });
}
