// Makes the files that no test loads count as 0 percent in the coverage report.
// `flutter test --coverage` only reports the files that a test loaded: a file
// that is never imported would be missing from coverage/lcov.info, and a layer
// could hide behind the files that happen to be tested. This script writes
// test/coverage_helper_test.dart, a test that imports every library under lib/
// (the way very_good_cli does), so that all of them are loaded and measured.
//
//   dart run tool/coverage_helper.dart && flutter test --coverage
//
// The generated file is ignored by Git (see .gitignore) and rewritten on every
// run. Generated libraries (tool/coverage_gate.dart lists them) and `part`
// files are not imported: the first are not measured, the second cannot be
// imported on their own.

import 'dart:io';

import 'coverage_gate.dart';

/// Where the test is written.
const helperTestPath = 'test/coverage_helper_test.dart';

const _pubspecPath = 'pubspec.yaml';
const _packageNamePattern = r'^name:\s*([A-Za-z0-9_]+)\s*$';
const _partOfPattern = r'^\s*part\s+of\b';
const _libPrefix = '$sourceFolder/';

/// Header of the generated test. The imports are there to be loaded, not used.
const _header = '''
// Written by `dart run tool/coverage_helper.dart`, ignored by Git: do not edit.
// It loads every library under lib/, so that the files no test imports count as
// 0% in the coverage.
// ignore_for_file: directives_ordering, unused_import
''';

/// Reads the name of the package from the content of its pubspec.yaml.
String readPackageName(String pubspec) {
  final match = RegExp(
    _packageNamePattern,
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw const FormatException('pubspec.yaml has no "name:" entry.');
  }
  return match.group(1)!;
}

/// Whether the source of a Dart file is a `part` of another library, which
/// cannot be imported.
bool isPartFile(String source) =>
    RegExp(_partOfPattern, multiLine: true).hasMatch(source);

/// The content of the generated test, from the name of the package and the
/// paths of its libraries (relative to the package, such as
/// `lib/presentation/app.dart`). Sorted, so that two runs on the same code
/// write the same file.
String buildCoverageHelper(String packageName, Iterable<String> libraryPaths) {
  final imports = [
    for (final path in libraryPaths)
      "import 'package:$packageName/${path.substring(_libPrefix.length)}';",
  ]..sort();
  return '$_header\n${imports.join('\n')}\n\nvoid main() {}\n';
}

/// The libraries to load: every `.dart` file under lib/ that is neither
/// generated nor a part.
List<String> findLibraries(Directory lib) {
  return [
    for (final entity in lib.listSync(recursive: true))
      if (entity is File)
        if (normalizePath(entity.path) case final path
            when path.endsWith('.dart') &&
                !isGeneratedFile(path) &&
                !isPartFile(entity.readAsStringSync()))
          path,
  ];
}

/// Writes [helperTestPath] for the package in the current directory.
void main() {
  final lib = Directory(sourceFolder);
  if (!lib.existsSync()) {
    stderr.writeln(
      'Run this script from the root of the package: no $sourceFolder/ here.',
    );
    exitCode = 2;
    return;
  }
  final packageName = readPackageName(File(_pubspecPath).readAsStringSync());
  final libraries = findLibraries(lib);
  File(helperTestPath)
      .writeAsStringSync(buildCoverageHelper(packageName, libraries));
  stdout.writeln('Wrote $helperTestPath (${libraries.length} libraries).');
}
