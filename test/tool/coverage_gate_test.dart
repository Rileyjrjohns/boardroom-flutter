// Pure Dart: runs with `dart test test/tool`, without Flutter. The lcov samples
// are written by hand in the format of `flutter test --coverage` (lines only).

import 'package:test/test.dart';

import '../../tool/coverage_gate.dart';

/// One lcov record of a file with [covered] lines that ran, then [uncovered]
/// lines that did not.
String record(String path, {required int covered, int uncovered = 0}) {
  final lines = [
    for (var i = 1; i <= covered; i++) 'DA:$i,1',
    for (var i = covered + 1; i <= covered + uncovered; i++) 'DA:$i,0',
  ];
  return [
    'SF:$path',
    ...lines,
    'LF:${covered + uncovered}',
    'LH:$covered',
    'end_of_record',
  ].join('\n');
}

CoverageRow rowNamed(CoverageReport report, String label) =>
    report.rows.singleWhere((row) => row.label == label);

const domainLabel = '`lib/core/domain` + `lib/features/*/domain`';
const applicationLabel =
    '`lib/core/application` + `lib/features/*/application`';
const restLabel = 'Rest (all but domain and application)';
const totalLabel = 'Total (`lib`)';

void main() {
  group('parseLcov', () {
    test('counts the lines that hold code and the lines that ran', () {
      final files = parseLcov(
        'SF:lib/a.dart\nDA:1,3\nDA:2,0\nDA:3,1,abc123\nLF:3\nLH:2\n'
        'end_of_record\n',
      );

      expect(files, hasLength(1));
      expect(files.single.path, 'lib/a.dart');
      expect(files.single.total, 3);
      expect(files.single.covered, 2);
    });

    test('merges a file that is written twice, line by line', () {
      final files = parseLcov(
        'SF:lib/a.dart\nDA:1,0\nDA:2,0\nend_of_record\n'
        'SF:lib/a.dart\nDA:1,2\nend_of_record\n',
      );

      expect(files.single.total, 2);
      expect(files.single.covered, 1);
    });

    test('rejects a malformed record', () {
      expect(
        () => parseLcov('SF:lib/a.dart\nDA:one,two\nend_of_record\n'),
        throwsFormatException,
      );
      expect(() => parseLcov('DA:1,1\n'), throwsFormatException);
    });
  });

  group('isGeneratedFile', () {
    test('knows the build_runner and gen-l10n output', () {
      expect(
        isGeneratedFile(
          'lib/features/meetings/domain/entities/meeting.freezed.dart',
        ),
        isTrue,
      );
      expect(
        isGeneratedFile('lib/features/meetings/domain/entities/meeting.g.dart'),
        isTrue,
      );
      expect(
        isGeneratedFile('lib/app/persistence/boardroom_database.drift.dart'),
        isTrue,
      );
      expect(isGeneratedFile('lib/l10n/app_localizations.dart'), isTrue);
      expect(isGeneratedFile('lib/l10n/app_localizations_fr.dart'), isTrue);
      expect(
        isGeneratedFile('/work/boardroom/lib/core/domain/a.g.dart'),
        isTrue,
      );
      expect(isGeneratedFile(r'lib\l10n\app_localizations_en.dart'), isTrue);
    });

    test('keeps the files written by hand', () {
      expect(
        isGeneratedFile('lib/features/meetings/domain/entities/meeting.dart'),
        isFalse,
      );
      expect(isGeneratedFile('lib/app/app.dart'), isFalse);
      expect(isGeneratedFile('lib/generated_names.dart'), isFalse);
    });
  });

  group('evaluateCoverage', () {
    test('passes when every layer is above its threshold', () {
      final report = evaluateCoverage(
        [
          record('lib/core/domain/a.dart', covered: 9, uncovered: 1),
          record('lib/features/auth/application/b.dart', covered: 10),
          record('lib/app/c.dart', covered: 7, uncovered: 3),
        ].join('\n'),
      );

      expect(report.passed, isTrue);
      expect(rowNamed(report, domainLabel).verdict, Verdict.pass);
      expect(rowNamed(report, applicationLabel).verdict, Verdict.pass);
      expect(rowNamed(report, restLabel).verdict, Verdict.pass);
      expect(rowNamed(report, totalLabel).covered, 26);
      expect(rowNamed(report, totalLabel).total, 30);
    });

    test(
      'fails a layer that is under its own threshold, whatever the rest',
      () {
        final report = evaluateCoverage(
          [
            record('lib/core/domain/a.dart', covered: 89, uncovered: 11),
            record('lib/features/auth/application/b.dart', covered: 10),
            record('lib/app/c.dart', covered: 1000),
          ].join('\n'),
        );

        expect(report.passed, isFalse);
        expect(report.failures.map((row) => row.label), [domainLabel]);
        expect(rowNamed(report, restLabel).verdict, Verdict.pass);
      },
    );

    test('does not let a good layer lift the other one', () {
      final report = evaluateCoverage(
        [
          record('lib/core/domain/a.dart', covered: 1000),
          record(
            'lib/features/auth/application/b.dart',
            covered: 8,
            uncovered: 2,
          ),
        ].join('\n'),
      );

      expect(report.failures.map((row) => row.label), [applicationLabel]);
    });

    test('fails when everything else together is under 70 percent', () {
      final report = evaluateCoverage(
        [
          record('lib/core/domain/a.dart', covered: 10),
          record('lib/core/infrastructure/b.dart', covered: 6, uncovered: 4),
          record('lib/app/c.dart', covered: 7, uncovered: 13),
          record('lib/main.dart', covered: 0, uncovered: 2),
        ].join('\n'),
      );

      // 13 of 32 lines in the rest, and the total is dragged up by the domain.
      final rest = rowNamed(report, restLabel);
      expect(rest.covered, 13);
      expect(rest.total, 32);
      expect(rest.verdict, Verdict.fail);
      expect(report.failures.map((row) => row.label), [restLabel]);
      expect(report.passed, isFalse);
    });

    test('takes the gated layers out of the figure of the rest', () {
      // The domain is perfect, the rest is at 50 percent: the rest must not
      // be lifted by the domain.
      final report = evaluateCoverage(
        [
          record('lib/core/domain/a.dart', covered: 100),
          record('lib/app/c.dart', covered: 5, uncovered: 5),
        ].join('\n'),
      );

      final rest = rowNamed(report, restLabel);
      expect(rest.total, 10);
      expect(rest.percent, 50);
      expect(rest.verdict, Verdict.fail);
    });

    test('ignores generated files, which would otherwise fail the gate', () {
      final report = evaluateCoverage(
        [
          record('lib/core/domain/a.dart', covered: 10),
          record('lib/core/domain/a.freezed.dart', covered: 0, uncovered: 500),
          record('lib/core/domain/a.g.dart', covered: 0, uncovered: 500),
          record('lib/app/a.drift.dart', covered: 0, uncovered: 500),
          record('lib/l10n/app_localizations.dart', covered: 0, uncovered: 50),
          record(
            'lib/l10n/app_localizations_fr.dart',
            covered: 0,
            uncovered: 50,
          ),
          record('lib/app/c.dart', covered: 10),
        ].join('\n'),
      );

      expect(report.passed, isTrue);
      expect(rowNamed(report, totalLabel).total, 20);
      expect(rowNamed(report, domainLabel).total, 10);
    });

    test('skips a layer that has no code', () {
      final report = evaluateCoverage(
        record('lib/app/c.dart', covered: 8, uncovered: 2),
      );

      expect(rowNamed(report, domainLabel).verdict, Verdict.skipped);
      expect(rowNamed(report, applicationLabel).verdict, Verdict.skipped);
      expect(report.passed, isTrue);
    });

    test('skips every gate on an empty report', () {
      final report = evaluateCoverage('');

      expect(report.passed, isTrue);
      expect(rowNamed(report, restLabel).verdict, Verdict.skipped);
    });

    test('counts a file that no test loaded as 0 percent', () {
      final report = evaluateCoverage(
        [
          record('lib/core/domain/a.dart', covered: 10),
          record(
            'lib/features/auth/domain/never_loaded.dart',
            covered: 0,
            uncovered: 10,
          ),
        ].join('\n'),
      );

      expect(rowNamed(report, domainLabel).percent, 50);
      expect(report.failures.map((row) => row.label), [domainLabel]);
    });

    test('cuts the percentage instead of rounding it', () {
      // 8999 of 10000 lines is 89.99, which must not read as the 90 of the
      // gate.
      final report = evaluateCoverage(
        record('lib/core/domain/a.dart', covered: 8999, uncovered: 1001),
      );

      final domain = rowNamed(report, domainLabel);
      expect(domain.percent, 89.99);
      expect(domain.verdict, Verdict.fail);
    });

    test('accepts a layer that is exactly on its threshold', () {
      final report = evaluateCoverage(
        record('lib/core/domain/a.dart', covered: 90, uncovered: 10),
      );

      expect(rowNamed(report, domainLabel).verdict, Verdict.pass);
    });

    test('accepts absolute paths and Windows separators', () {
      final report = evaluateCoverage(
        [
          record(
            '/work/boardroom/lib/features/auth/domain/a.dart',
            covered: 10,
          ),
          record(r'lib\core\application\b.dart', covered: 0, uncovered: 10),
        ].join('\n'),
      );

      expect(rowNamed(report, domainLabel).verdict, Verdict.pass);
      expect(rowNamed(report, applicationLabel).verdict, Verdict.fail);
    });

    test('does not mix a domain folder with a folder that starts with it', () {
      final report = evaluateCoverage(
        [
          record('lib/core/domainish/a.dart', covered: 0, uncovered: 10),
          record(
            'lib/features/auth/domainish/a.dart',
            covered: 0,
            uncovered: 10,
          ),
          record('lib/features/domain/a.dart', covered: 0, uncovered: 10),
        ].join('\n'),
      );

      expect(rowNamed(report, domainLabel).total, 0);
      expect(rowNamed(report, restLabel).total, 30);
    });
  });

  group('toMarkdown', () {
    test('prints a table with lines, percent, threshold and result', () {
      final markdown = evaluateCoverage(
        [
          record('lib/core/domain/a.dart', covered: 9, uncovered: 1),
          record(
            'lib/features/auth/application/b.dart',
            covered: 1,
            uncovered: 1,
          ),
          record('lib/app/c.dart', covered: 7, uncovered: 3),
        ].join('\n'),
      ).toMarkdown();

      expect(markdown, contains('### Test coverage (lines)'));
      expect(markdown, contains('Lines only'));
      expect(
        markdown,
        contains(
          '| `lib/core/domain` + `lib/features/*/domain` | 9 / 10 | 90.00 % '
          '| 90 % | pass |',
        ),
      );
      expect(
        markdown,
        contains(
          '| `lib/core/application` + `lib/features/*/application` | 1 / 2 '
          '| 50.00 % | 90 % | fail |',
        ),
      );
      expect(
        markdown,
        contains(
          '| Rest (all but domain and application) | 7 / 10 | 70.00 % '
          '| 70 % | pass |',
        ),
      );
      expect(
        markdown,
        contains('| `lib/app` | 7 / 10 | 70.00 % | in rest | - |'),
      );
    });

    test('shows a dash for a scope with nothing to measure', () {
      final markdown = evaluateCoverage('').toMarkdown();

      expect(
        markdown,
        contains(
          '| `lib/core/domain` + `lib/features/*/domain` | 0 / 0 | - | 90 % '
          '| skipped (no code) |',
        ),
      );
    });
  });
}
