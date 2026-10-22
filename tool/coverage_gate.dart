// The coverage gate of the CI, and the table it shows on the page of a run. It
// reads coverage/lcov.info (written by `flutter test --coverage`) and checks
// two kinds of threshold:
//
// - 90 percent for each of lib/domain and lib/application, each on its own. A
//   layer is checked as soon as it has code to measure; while it is empty, it
//   is skipped.
// - 70 percent for everything else together (infrastructure, presentation, di
//   and the rest of lib/). The files that have a threshold of their own are
//   taken out of this figure, as Jest does for the RN repo.
//
// lcov from `flutter test` has lines only: there is no branch nor function
// data, so every figure here is a line figure. Generated files (see below) are
// ignored. Files that no test loads are absent from lcov;
// tool/coverage_helper.dart makes them show up with 0 percent.
//
//   dart run tool/coverage_gate.dart [lcov.info] >> "$GITHUB_STEP_SUMMARY"
//
// Exit code: 0 when every gate passes, 1 when one fails, 2 when the lcov file
// cannot be read. All the work is done by evaluateCoverage, which is tested
// (test/tool/coverage_gate_test.dart); the rest is the reading and the
// printing.

import 'dart:convert';
import 'dart:io';

/// Where `flutter test --coverage` writes its report.
const defaultLcovPath = 'coverage/lcov.info';

/// The folder of the source code that is measured.
const sourceFolder = 'lib';

/// Endings of the files that build_runner writes (freezed, json_serializable,
/// riverpod_generator).
const generatedFileSuffixes = ['.g.dart', '.freezed.dart'];

/// Start of the path of the files that gen-l10n writes
/// (`app_localizations.dart` and one file per language), see l10n.yaml.
const generatedL10nPrefix = 'lib/l10n/app_localizations';

/// Gate of each of the two layers that hold the rules, in percent of lines.
const layerThresholdPercent = 90;

/// Gate of everything else together, in percent of lines.
const restThresholdPercent = 70;

const _domainFolder = 'lib/domain';
const _applicationFolder = 'lib/application';
const _infrastructureFolder = 'lib/infrastructure';
const _presentationFolder = 'lib/presentation';
const _diFolder = 'lib/di';

const _title = '### Test coverage (lines)';
const _lineOnlyNote =
    'Lines only: `flutter test --coverage` writes no branch nor function data. '
    'Generated files are left out.';
const _header = [
  'Scope',
  'Lines covered / total',
  'Coverage',
  'Threshold',
  'Result',
];
const _alignment = ['---', '---:', '---:', '---:', '---'];
const _noValue = '-';
const _noThreshold = 'none';
const _partOfRest = 'in rest';
const _passed = 'pass';
const _failed = 'fail';
const _skipped = 'skipped (no code)';
const _decimals = 2;
const _percentScale = 100;

/// Turns Windows separators into `/`, so that the checks below read one form of
/// path.
String normalizePath(String path) => path.replaceAll(r'\', '/');

/// Whether a file is generated: build_runner output or the gen-l10n classes.
/// The path may be relative to the package (`lib/a.g.dart`) or absolute.
bool isGeneratedFile(String path) {
  final normalized = normalizePath(path);
  if (generatedFileSuffixes.any(normalized.endsWith)) return true;
  final inL10nOutput =
      normalized.startsWith(generatedL10nPrefix) ||
      normalized.contains('/$generatedL10nPrefix');
  return inL10nOutput && normalized.endsWith('.dart');
}

/// Whether a file is under a folder (`lib/domain`). Absolute paths are
/// accepted, and `lib/domain` does not match `lib/domainish/`.
bool isUnder(String path, String folder) {
  final normalized = normalizePath(path);
  return normalized.startsWith('$folder/') || normalized.contains('/$folder/');
}

/// The lines of one file that hold code, and how many of them ran.
class FileCoverage {
  /// Creates the figures of one file.
  const new({required this.path, required this.total, required this.covered});

  /// Path as lcov wrote it, with `/` separators.
  final String path;

  /// Lines that hold code.
  final int total;

  /// Lines that ran at least once.
  final int covered;
}

/// Reads an lcov report. Only the `SF:` (file) and `DA:` (line and hit count)
/// records are used: the `LF` and `LH` totals are derived from them. A file
/// written twice is merged line by line.
List<FileCoverage> parseLcov(String content) {
  final hitsByLine = <String, Map<int, int>>{};
  Map<int, int>? current;
  for (final raw in const LineSplitter().convert(content)) {
    final line = raw.trim();
    if (line.startsWith('SF:')) {
      final path = normalizePath(line.substring(3));
      current = hitsByLine.putIfAbsent(path, () => <int, int>{});
    } else if (line.startsWith('DA:')) {
      if (current == null) {
        throw FormatException('A DA record comes before any SF record: $line');
      }
      // DA:<line number>,<hit count>[,<checksum>]
      final parts = line.substring(3).split(',');
      final number = parts.isEmpty ? null : int.tryParse(parts[0]);
      final hits = parts.length < 2 ? null : int.tryParse(parts[1]);
      if (number == null || hits == null) {
        throw FormatException('Malformed DA record: $line');
      }
      current[number] = (current[number] ?? 0) + hits;
    } else if (line == 'end_of_record') {
      current = null;
    }
  }
  return [
    for (final MapEntry(key: path, value: lines) in hitsByLine.entries)
      FileCoverage(
        path: path,
        total: lines.length,
        covered: lines.values.where((hits) => hits > 0).length,
      ),
  ];
}

/// How a row ended.
enum Verdict {
  /// The row has a threshold and meets it.
  pass,

  /// The row has a threshold and does not meet it.
  fail,

  /// The row has a threshold but nothing to measure.
  skipped,

  /// The row has no threshold of its own.
  none,
}

/// One row of the table: a scope, its lines and its threshold.
class CoverageRow {
  /// Creates a row. [thresholdPercent] is null for a row that is only
  /// informative.
  const new({
    required this.label,
    required this.covered,
    required this.total,
    this.thresholdPercent,
    this.note,
  });

  /// Name of the scope, in Markdown.
  final String label;

  /// Lines that ran.
  final int covered;

  /// Lines that hold code.
  final int total;

  /// Gate in percent, or null for none.
  final int? thresholdPercent;

  /// Shown in place of the threshold when the row has none.
  final String? note;

  /// The percentage covered, cut (not rounded) to two decimals, as Istanbul
  /// does for Jest: a scope under its gate never shows the gate (89.996 is
  /// 89.99, not 90.00). Null when there is nothing to measure.
  double? get percent {
    if (total == 0) return null;
    return (covered * 100 * _percentScale ~/ total) / _percentScale;
  }

  /// The percentage as the table shows it, or a dash when there is nothing to
  /// measure.
  String get percentText {
    final value = percent;
    return value == null ? _noValue : '${value.toStringAsFixed(_decimals)} %';
  }

  /// The threshold as the table shows it: the gate, or the note of the row.
  String get thresholdText {
    final threshold = thresholdPercent;
    return threshold == null ? (note ?? _noThreshold) : '$threshold %';
  }

  /// Pass, fail, or why there is no verdict. Compared with integers, so there
  /// is no rounding.
  Verdict get verdict {
    final threshold = thresholdPercent;
    if (threshold == null) return Verdict.none;
    if (total == 0) return Verdict.skipped;
    return covered * 100 >= threshold * total ? Verdict.pass : Verdict.fail;
  }
}

/// The rows of the table and what they say together.
class CoverageReport {
  /// Creates a report from its rows.
  const new(this.rows);

  /// The rows, in the order of the table.
  final List<CoverageRow> rows;

  /// The rows that do not meet their threshold.
  List<CoverageRow> get failures =>
      rows.where((row) => row.verdict == Verdict.fail).toList();

  /// True when no gate fails.
  bool get passed => failures.isEmpty;

  /// The table in Markdown, ready for the summary of a CI run.
  String toMarkdown() {
    String cells(List<String> values) => '| ${values.join(' | ')} |';
    return [
      _title,
      '',
      _lineOnlyNote,
      '',
      cells(_header),
      cells(_alignment),
      for (final row in rows) cells(_cellsOf(row)),
      '',
    ].join('\n');
  }

  List<String> _cellsOf(CoverageRow row) => [
    row.label,
    '${row.covered} / ${row.total}',
    row.percentText,
    row.thresholdText,
    switch (row.verdict) {
      Verdict.pass => _passed,
      Verdict.fail => _failed,
      Verdict.skipped => _skipped,
      Verdict.none => _noValue,
    },
  ];
}

/// Builds the report from the content of an lcov file: generated files are
/// dropped, then the lines are added up per scope (sum of what ran over sum of
/// what holds code, not the mean of the figures of the files).
CoverageReport evaluateCoverage(String lcov) {
  final files = parseLcov(lcov).where((f) => !isGeneratedFile(f.path)).toList();

  CoverageRow rowOf(
    String label,
    bool Function(FileCoverage file) isInScope, {
    int? thresholdPercent,
    String? note,
  }) {
    final inScope = files.where(isInScope);
    return CoverageRow(
      label: label,
      covered: inScope.fold(0, (sum, file) => sum + file.covered),
      total: inScope.fold(0, (sum, file) => sum + file.total),
      thresholdPercent: thresholdPercent,
      note: note,
    );
  }

  bool isGatedLayer(FileCoverage file) =>
      isUnder(file.path, _domainFolder) ||
      isUnder(file.path, _applicationFolder);

  return CoverageReport([
    rowOf('Total (`$sourceFolder`)', (_) => true),
    rowOf(
      '`$_domainFolder`',
      (file) => isUnder(file.path, _domainFolder),
      thresholdPercent: layerThresholdPercent,
    ),
    rowOf(
      '`$_applicationFolder`',
      (file) => isUnder(file.path, _applicationFolder),
      thresholdPercent: layerThresholdPercent,
    ),
    rowOf(
      'Rest (all but domain and application)',
      (file) => !isGatedLayer(file),
      thresholdPercent: restThresholdPercent,
    ),
    for (final folder in [
      _infrastructureFolder,
      _presentationFolder,
      _diFolder,
    ])
      rowOf(
        '`$folder`',
        (file) => isUnder(file.path, folder),
        note: _partOfRest,
      ),
  ]);
}

/// Reads the lcov file, prints the table and sets the exit code.
void main(List<String> arguments) {
  final path = arguments.isEmpty ? defaultLcovPath : arguments.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln(
      'Cannot build the coverage table: $path does not exist. '
      'Run `dart run tool/coverage_helper.dart`, then '
      '`flutter test --coverage`.',
    );
    exitCode = 2;
    return;
  }
  final CoverageReport report;
  try {
    report = evaluateCoverage(file.readAsStringSync());
  } on FormatException catch (error) {
    stderr.writeln('Cannot read $path: ${error.message}');
    exitCode = 2;
    return;
  }
  stdout.write(report.toMarkdown());
  for (final row in report.failures) {
    stderr.writeln(
      'Coverage gate failed: ${row.label} has ${row.percentText} of its lines '
      'covered, ${row.thresholdPercent} % is required.',
    );
  }
  if (!report.passed) exitCode = 1;
}
