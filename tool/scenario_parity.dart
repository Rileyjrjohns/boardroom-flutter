// Checks that the Flutter tests of the domain and of the application are the
// scenarios of the React Native ones, one for one.
//
// The showcase says that a well-made hexagonal architecture makes the domain
// portable. The proof is that the Dart domain and application pass the same
// scenarios as the TypeScript ones. This script lists the tests of the React
// Native repository (src/domain and src/application, the *.test.ts files),
// maps each file to its Dart test file (the one file of the pure Dart test
// folders, test/core, test/features/*, test/app/composition and test/support,
// that has the snake case
// name of the React Native one, see dartTestPathFor), lists the tests that
// `dart test` reports for the Dart files, and compares the full names of the
// two sides: a scenario of the React Native repository that has no Dart test of
// the same name is a gap, and a Dart test with no React Native counterpart is
// an extra that must be explained.
//
//   dart run tool/scenario_parity.dart --rn ../boardroom
//   dart run tool/scenario_parity.dart --rn ../boardroom --only src/domain/shared
//   dart run tool/scenario_parity.dart --rn ../boardroom --only src/application/use-cases --table
//
// What is compared, and how the names are formed, is written in docs/porting.md
// ("Tests"). The differences that are on purpose are written in
// docs/parity/exceptions.md (a React Native scenario that cannot exist in Dart)
// and docs/parity/extras.md (a Dart test that React Native has no scenario for).
//
// Options:
//   --rn <path>          the checkout of the React Native repository (required)
//   --only <prefix>      only the React Native test files whose path starts
//                        with the prefix, for example src/domain/value-objects
//                        (repeatable)
//   --table              print the parity table of the use cases (Markdown)
//   --rn-names <file>    read the React Native names from the JSON that
//                        `jest --json` writes, instead of reading the sources
//   --dart-names <file>  read the Dart names from the output of
//                        `dart test --reporter json`, instead of running it
//   --root <path>        the Flutter project (default: the current directory)
//
// Exit code: 0 when every scenario is accounted for, 1 when there is an
// unexplained difference, 2 when the script cannot run.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ts_test_names.dart';

/// Folders of the React Native repository whose tests are compared.
const List<String> rnTestFolders = ['src/domain', 'src/application'];

/// Suffix of a React Native test file.
const String rnTestSuffix = '.test.ts';

/// Suffix of a Dart test file.
const String dartTestSuffix = '_test.dart';

/// Folder of the React Native test support (fakes, builders, contracts); its
/// Dart counterpart is `support`.
const String rnSupportFolder = 'testing';

/// Dart name of the support folder.
const String dartSupportFolder = 'support';

/// Folder of the Dart tests.
const String dartTestFolder = 'test';

/// The layers of the React Native repository whose tests are compared. They
/// are also the names of the layer folders of the Dart core and features.
const List<String> parityLayers = ['domain', 'application'];

/// The layer whose React Native tests are kept beside the Dart support code:
/// the fakes and their tests are in [dartSupportFolder].
const String supportLayer = 'application';

/// Folder of the Dart core, under [dartTestFolder].
const String dartCoreFolder = 'core';

/// Folder of the Dart features, under [dartTestFolder].
const String dartFeaturesFolder = 'features';

/// The pure test folder of the composition, under [dartTestFolder]: the tests
/// of the glue between features (`app/composition`), which run under
/// `dart test` and count as the application, like the support code.
const String dartCompositionFolder = 'app/composition';

/// The folders of [dartSupportFolder] that are pure Dart, so that `dart test`
/// runs the tests they hold: the builders, the contract suites and the fakes.
/// The support of the infrastructure needs Flutter and is never run here.
const List<String> pureSupportFolders = ['builders', 'contracts', 'fakes'];

/// The path shown for a React Native test file that has no Dart test file.
const String missingDartFolder = '$dartTestFolder/**';

/// File that lists the React Native scenarios that cannot exist in Dart.
const String exceptionsFile = 'docs/parity/exceptions.md';

/// File that lists the Dart tests that React Native has no scenario for.
const String extrasFile = 'docs/parity/extras.md';

/// What an extras entry says when the whole Dart file is Dart specific.
const String wholeFileMarker = '*';

/// A part of a React Native test file that a Dart test file of its own takes
/// over.
class SplitPart {
  /// Creates the part: the scenarios whose full names start with one of
  /// [scenarioPrefixes] are expected in the Dart test file named
  /// [dartFileName].
  const new({required this.dartFileName, required this.scenarioPrefixes});

  /// The name of the Dart test file (`with_vote_recorded_test.dart`), looked
  /// for among the Dart test files like the name of a whole file is (see
  /// [dartTestPathFor]).
  final String dartFileName;

  /// The beginnings of the full names of the scenarios of this part: the
  /// description of a `describe` that holds them and the space after it, or the
  /// description of a `describe` and the beginning of the title of a test.
  final List<String> scenarioPrefixes;

  /// Whether the scenario named [name] belongs to this part.
  bool takes(String name) => scenarioPrefixes.any(name.startsWith);
}

/// The React Native test files whose scenarios are in several Dart test files,
/// because the code they test is not in one module of the Dart port. The
/// scenarios named by a [SplitPart] are expected in its Dart file, and all the
/// others in the file the name of the React Native file gives, as for any other
/// file. Every entry is a deviation from the React Native structure, written in
/// docs/parity/open-questions.md.
///
/// - `Meeting.test.ts` tests `withVoteRecorded` with the meeting. In Dart the
///   function belongs to the votes, which depend on the meetings and not the
///   other way round, so its scenarios are in the votes.
/// - `errors.test.ts` tests the errors of every family. In Dart each family is
///   in the feature that owns it (the core keeps the repository, storage and
///   validation errors), so its scenarios are in that feature, and the one
///   about the codes of every family is in the composition, the only place that
///   sees them all.
const Map<String, List<SplitPart>> splitScenarioFiles = {
  'src/domain/entities/Meeting.test.ts': [
    SplitPart(
      dartFileName: 'with_vote_recorded_test.dart',
      scenarioPrefixes: ['withVoteRecorded '],
    ),
  ],
  'src/domain/errors/errors.test.ts': [
    SplitPart(
      dartFileName: 'error_codes_test.dart',
      scenarioPrefixes: ['error codes '],
    ),
    SplitPart(
      dartFileName: 'auth_errors_test.dart',
      scenarioPrefixes: [
        'error factories build the authentication errors',
        'error factories build the biometric errors',
      ],
    ),
    SplitPart(
      dartFileName: 'screen_protection_errors_test.dart',
      scenarioPrefixes: ['error factories build the screen protection errors'],
    ),
    SplitPart(
      dartFileName: 'vote_errors_test.dart',
      scenarioPrefixes: ['vote delivery errors ', 'isVotingError '],
    ),
  ],
};

/// The layer (`domain` or `application`) of the React Native test file
/// [rnTestPath] (relative to the React Native repository), or null when the
/// path is not one of a test of the domain or of the application.
String? parityLayerOf(String rnTestPath) {
  if (!rnTestPath.endsWith(rnTestSuffix)) {
    return null;
  }
  final segments = rnTestPath.split('/');
  if (segments.length < 3 ||
      segments.first != 'src' ||
      !parityLayers.contains(segments[1])) {
    return null;
  }
  return segments[1];
}

/// The Dart path of the test file that stands for the React Native test file
/// [rnTestPath] (relative to the React Native repository), or null when the
/// path is not one of a test of the domain or of the application.
///
/// It is the file of [dartTestFiles] (project-relative paths with `/`, the
/// Dart tests that are compared) whose name is the snake case of the name of
/// the React Native one: `src/domain/value-objects/EmailAddress.test.ts` is
/// `email_address_test.dart`, `src/application/testing/fakes.contracts.test.ts`
/// is `fakes_contracts_test.dart`. Two files may have the same name in two
/// layers (`app_lock_test.dart` tests a policy of the domain and a function of
/// the application): then the file in a folder named after the layer of the
/// React Native one is meant. When no file has the name, the result is
/// `test/**/<name>`, a path that stands for the missing file in the report.
///
/// Throws a [FormatException] when several files are still possible: the
/// comparison would be a guess.
String? dartTestPathFor(String rnTestPath, Iterable<String> dartTestFiles) {
  final layer = parityLayerOf(rnTestPath);
  if (layer == null) {
    return null;
  }
  final fileName = p.posix.basename(rnTestPath);
  final stem = fileName.substring(0, fileName.length - rnTestSuffix.length);
  final dartName = '${snakeCase(stem)}$dartTestSuffix';
  return _dartPathNamed(dartName, layer, dartTestFiles, rnTestPath);
}

/// The Dart file named [dartName] among [dartTestFiles], the one in a folder
/// named after [layer] when two files share the name; `test/**/<name>` when
/// there is none. Throws a [FormatException] (with [what] in the message) when
/// the choice is a guess.
String _dartPathNamed(
  String dartName,
  String layer,
  Iterable<String> dartTestFiles,
  String what,
) {
  final named = {
    for (final file in dartTestFiles)
      if (p.posix.basename(file) == dartName) file,
  }.toList()..sort();
  if (named.isEmpty) {
    return '$missingDartFolder/$dartName';
  }
  if (named.length == 1) {
    return named.single;
  }
  final inLayer = [
    for (final file in named)
      if (p.posix.dirname(file).split('/').contains(layer)) file,
  ];
  if (inLayer.length == 1) {
    return inLayer.single;
  }
  throw FormatException(
    '$what has several Dart test files named $dartName and none can be '
    'chosen by its layer ($layer): ${named.join(', ')}',
  );
}

String _dartSegment(String segment) =>
    segment == rnSupportFolder ? dartSupportFolder : snakeCase(segment);

/// Whether the Dart test file [dartFile] is in the folder that the React
/// Native path prefix [rnPrefix] (the value of `--only`) stands for, to find
/// the Dart-only files of a folder.
///
/// The prefix `src/<layer>` stands for the files in a folder named after the
/// layer (`test/features/auth/domain/...`, `test/core/application/...`); the
/// fakes and their tests are in `test/support`, which counts as the
/// application. Each further segment of the prefix, in snake case with
/// `testing` as `support`, must appear in the path of the file, one after the
/// other: `src/domain/value-objects` stands for the files in a folder
/// `domain/value_objects`, `src/application/testing` for the files in
/// `test/support`.
bool dartFileMatchesPrefix(String dartFile, String rnPrefix) {
  final segments = rnPrefix.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.length < 2 ||
      segments.first != 'src' ||
      !parityLayers.contains(segments[1])) {
    return false;
  }
  final layer = segments[1];
  final folders = p.posix.dirname(dartFile).split('/');
  final inSupport =
      layer == supportLayer &&
      (folders.contains(dartSupportFolder) ||
          p.posix
              .dirname(dartFile)
              .startsWith('$dartTestFolder/$dartCompositionFolder'));
  if (!folders.contains(layer) && !inSupport) {
    return false;
  }
  final wanted = [
    for (final segment in segments.skip(2)) _dartSegment(segment),
  ];
  if (wanted.isEmpty) {
    return true;
  }
  for (var start = 0; start + wanted.length <= folders.length; start++) {
    if (folders.sublist(start, start + wanted.length).join('/') ==
        wanted.join('/')) {
      return true;
    }
  }
  return false;
}

/// `FooBar` and `fooBar` are `foo_bar`, `use-cases` is `use_cases`,
/// `fakes.contracts` is `fakes_contracts`.
String snakeCase(String name) => name
    .replaceAll(RegExp('[-.]'), '_')
    .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
    .replaceAllMapped(RegExp('([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}')
    .toLowerCase();

/// A line of docs/parity/exceptions.md or docs/parity/extras.md: the file, the
/// full name of the test and why.
class ParityNote {
  /// Creates a note.
  const new({required this.file, required this.test, required this.reason});

  /// The test file: the React Native one in exceptions.md, the Dart one in
  /// extras.md.
  final String file;

  /// The full name of the test, or [wholeFileMarker] for every test of the
  /// file (extras only).
  final String test;

  /// The one-line reason.
  final String reason;
}

/// Reads the notes of an exceptions.md or extras.md: the rows of the Markdown
/// tables whose first two cells are code spans, `| `file` | `test name` |
/// reason |`. A `|` inside the name is written `\|`. A name that holds a
/// backtick is written between double backticks.
List<ParityNote> parseParityNotes(String markdown) {
  final notes = <ParityNote>[];
  final row = RegExp(
    r'^\|\s*`([^`]+)`\s*\|\s*(``(?:.+?)``|`(?:[^`]*)`)\s*\|\s*(.*?)\s*\|\s*$',
  );
  for (final line in const LineSplitter().convert(markdown)) {
    final match = row.firstMatch(line);
    if (match == null) {
      continue;
    }
    var test = match.group(2)!;
    test = test.startsWith('``')
        ? test.substring(2, test.length - 2).trim()
        : test.substring(1, test.length - 1);
    notes.add(
      ParityNote(
        file: match.group(1)!,
        test: test.replaceAll(r'\|', '|'),
        reason: match.group(3)!,
      ),
    );
  }
  return notes;
}

/// The tests that `dart test --reporter json` reported, by test file.
class DartTestReport {
  /// Creates a report.
  const new({required this.tests, required this.loadErrors});

  /// The full names of the tests (skipped ones included), by project-relative
  /// path of the test file, in the order they ran.
  final Map<String, List<String>> tests;

  /// The files that could not be loaded (they do not compile, for example).
  final List<String> loadErrors;
}

/// Reads the output of `dart test --reporter json`. [root] is the project
/// folder, to make the paths relative.
DartTestReport parseDartTestEvents(String output, {String? root}) {
  final suites = <int, String>{};
  final names = <int, (String, int)>{};
  final tests = <String, List<String>>{};
  final loadErrors = <String>[];
  for (final line in const LineSplitter().convert(output)) {
    if (!line.startsWith('{')) {
      continue;
    }
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (event is! Map<String, Object?>) {
      continue;
    }
    switch (event['type']) {
      case 'suite':
        final suite = event['suite']! as Map<String, Object?>;
        var path = suite['path']! as String;
        if (root != null && p.isAbsolute(path)) {
          path = p.relative(path, from: root);
        }
        suites[suite['id']! as int] = p.posix.joinAll(p.split(path));
      case 'testStart':
        final test = event['test']! as Map<String, Object?>;
        names[test['id']! as int] = (
          test['name']! as String,
          test['suiteID']! as int,
        );
      case 'testDone':
        final entry = names[event['testID']! as int];
        if (entry == null) {
          continue;
        }
        final (name, suiteId) = entry;
        final path = suites[suiteId];
        if (path == null) {
          continue;
        }
        if (name.startsWith('loading ')) {
          if (event['result'] == 'error') {
            loadErrors.add(path);
          }
          continue;
        }
        if (event['hidden'] == true) {
          continue;
        }
        tests.putIfAbsent(path, () => []).add(name);
    }
  }
  return DartTestReport(tests: tests, loadErrors: loadErrors);
}

/// The result of comparing the tests of one React Native test file with the
/// ones of its Dart counterpart.
class FileParity {
  /// Creates the result for [rnFile] and [dartFile].
  const new({
    required this.rnFile,
    required this.dartFile,
    required this.rnCount,
    required this.dartCount,
    required this.dartFileExists,
    this.missing = const [],
    this.extra = const [],
    this.excepted = const [],
    this.staleExceptions = const [],
    this.problems = const [],
  });

  /// The React Native test file, relative to its repository. Empty for a Dart
  /// file with no React Native counterpart.
  final String rnFile;

  /// The Dart test file, relative to the project.
  final String dartFile;

  /// Number of React Native tests, expanded.
  final int rnCount;

  /// Number of Dart tests.
  final int dartCount;

  /// Whether the Dart file has any test.
  final bool dartFileExists;

  /// React Native scenarios with no Dart test of the same name.
  final List<String> missing;

  /// Dart tests with no React Native scenario and no entry in extras.md.
  final List<String> extra;

  /// React Native scenarios that exceptions.md explains.
  final List<String> excepted;

  /// Entries of the notes that no longer match anything.
  final List<String> staleExceptions;

  /// Other problems (a file that does not load, a note that is not needed).
  final List<String> problems;

  /// Whether the file has no unexplained difference.
  bool get ok =>
      missing.isEmpty &&
      extra.isEmpty &&
      staleExceptions.isEmpty &&
      problems.isEmpty;

  /// The same result, with one more problem.
  FileParity withProblem(String problem) => FileParity(
    rnFile: rnFile,
    dartFile: dartFile,
    rnCount: rnCount,
    dartCount: dartCount,
    dartFileExists: dartFileExists,
    missing: missing,
    extra: extra,
    excepted: excepted,
    staleExceptions: staleExceptions,
    problems: [...problems, problem],
  );
}

/// The result of the whole comparison.
class ParityReport {
  /// Creates a report.
  const new(this.files);

  /// One entry per React Native test file (and per Dart-only file), by path.
  final List<FileParity> files;

  /// Whether every scenario is accounted for.
  bool get ok => files.every((file) => file.ok);

  /// Number of React Native scenarios.
  int get rnCount => files.fold(0, (sum, file) => sum + file.rnCount);

  /// Number of Dart tests.
  int get dartCount => files.fold(0, (sum, file) => sum + file.dartCount);
}

/// Compares the React Native tests [rnTests] (by React Native test file) with
/// the Dart tests [dartTests] (by Dart test file).
///
/// - The Dart file of a React Native file is found among [dartTestFiles] (see
///   [dartTestPathFor]); when it is null, the files that [dartTests] and
///   [dartLoadErrors] name. Throws a [FormatException] when two Dart files are
///   possible.
/// - A React Native scenario matches a Dart test of the same full name. A
///   scenario whose name holds a wildcard (a title the reader of the sources
///   could not compute) matches any Dart test whose name fits the rest.
/// - A scenario in [exceptions] is not expected in Dart. An exception for a
///   scenario that does not exist, or that Dart does test, is itself a problem:
///   the list must stay true.
/// - A Dart test with no scenario is an extra: it must be in [extras], for its
///   Dart file, by name or with [wholeFileMarker].
/// - [only] restricts the comparison to the React Native files whose path
///   starts with one of the prefixes, and to the Dart-only files of the same
///   folders (see [dartFileMatchesPrefix]). Empty means everything.
ParityReport compareScenarios({
  required Map<String, List<TsTest>> rnTests,
  required Map<String, List<String>> dartTests,
  List<ParityNote> exceptions = const [],
  List<ParityNote> extras = const [],
  List<String> only = const [],
  Set<String> dartLoadErrors = const {},
  Iterable<String>? dartTestFiles,
  Map<String, List<SplitPart>> splits = splitScenarioFiles,
}) {
  final candidates = List<String>.of(
    dartTestFiles ?? {...dartTests.keys, ...dartLoadErrors},
  );
  bool inScope(String rnFile) => only.isEmpty || only.any(rnFile.startsWith);
  bool dartInScope(String dartFile) =>
      only.isEmpty ||
      only.any((prefix) => dartFileMatchesPrefix(dartFile, prefix));

  final results = <FileParity>[];
  final mappedDart = <String>{};
  for (final rnFile in rnTests.keys.toList()..sort()) {
    if (!inScope(rnFile)) {
      continue;
    }
    final dartFile = dartTestPathFor(rnFile, candidates);
    if (dartFile == null) {
      continue;
    }

    // The scenarios that a declared split sends to another Dart file are
    // compared there; the others are compared with the file of the name.
    var rn = rnTests[rnFile]!;
    var rnNotes = [
      for (final note in exceptions)
        if (note.file == rnFile) note,
    ];
    final layer = parityLayerOf(rnFile)!;
    for (final part in splits[rnFile] ?? const <SplitPart>[]) {
      final partFile = _dartPathNamed(
        part.dartFileName,
        layer,
        candidates,
        rnFile,
      );
      bool inPart(String name) => part.takes(name);
      final taken = [
        for (final test in rn)
          if (inPart(test.displayName)) test,
      ];
      final takenNotes = [
        for (final note in rnNotes)
          if (inPart(note.test)) note,
      ];
      rn = [
        for (final test in rn)
          if (!inPart(test.displayName)) test,
      ];
      rnNotes = [
        for (final note in rnNotes)
          if (!inPart(note.test)) note,
      ];
      mappedDart.add(partFile);
      final compared = _compareFile(
        rnFile: rnFile,
        dartFile: partFile,
        rn: taken,
        dart: dartTests[partFile] ?? const [],
        exceptions: takenNotes,
        extras: [
          for (final note in extras)
            if (note.file == partFile) note,
        ],
        loadError: dartLoadErrors.contains(partFile),
      );
      results.add(
        taken.isEmpty
            ? compared.withProblem(
                'the split of $rnFile sends the scenarios that start with '
                '"${part.scenarioPrefixes.join('", "')}" here, and it has '
                'none',
              )
            : compared,
      );
    }

    mappedDart.add(dartFile);
    results.add(
      _compareFile(
        rnFile: rnFile,
        dartFile: dartFile,
        rn: rn,
        dart: dartTests[dartFile] ?? const [],
        exceptions: rnNotes,
        extras: [
          for (final note in extras)
            if (note.file == dartFile) note,
        ],
        loadError: dartLoadErrors.contains(dartFile),
      ),
    );
  }

  // The Dart files that no React Native file maps to.
  final dartOnly = {
    ...dartTests.keys,
    for (final note in extras) note.file,
  }.where((file) => !mappedDart.contains(file) && dartInScope(file));
  for (final dartFile in dartOnly.toList()..sort()) {
    results.add(
      _compareFile(
        rnFile: '',
        dartFile: dartFile,
        rn: const [],
        dart: dartTests[dartFile] ?? const [],
        exceptions: const [],
        extras: [
          for (final note in extras)
            if (note.file == dartFile) note,
        ],
        loadError: dartLoadErrors.contains(dartFile),
      ),
    );
  }

  // Exceptions written for a React Native file that has no tests at all.
  for (final note in exceptions) {
    if (inScope(note.file) && !rnTests.containsKey(note.file)) {
      results.add(
        FileParity(
          rnFile: note.file,
          dartFile: dartTestPathFor(note.file, candidates) ?? '',
          rnCount: 0,
          dartCount: 0,
          dartFileExists: false,
          staleExceptions: [
            '${note.test} (the React Native file has no such test)',
          ],
        ),
      );
    }
  }
  return ParityReport(results);
}

FileParity _compareFile({
  required String rnFile,
  required String dartFile,
  required List<TsTest> rn,
  required List<String> dart,
  required List<ParityNote> exceptions,
  required List<ParityNote> extras,
  required bool loadError,
}) {
  final remainingDart = List<String>.of(dart);
  final missing = <String>[];
  final excepted = <String>[];
  final stale = <String>[];
  final problems = <String>[];
  if (loadError) {
    problems.add(
      'the Dart test file does not load (see the output of dart test)',
    );
  }

  // The scenarios that cannot exist in Dart.
  final pending = List<TsTest>.of(rn);
  for (final note in exceptions) {
    final index = pending.indexWhere(
      (test) => test.hasWildcard
          ? test.pattern.hasMatch(note.test)
          : test.displayName == note.test,
    );
    if (index < 0) {
      stale.add('${note.test} (not a scenario of $rnFile)');
      continue;
    }
    pending.removeAt(index);
    excepted.add(note.test);
    if (remainingDart.contains(note.test)) {
      problems.add(
        'the exception for "${note.test}" is not needed: Dart has the test',
      );
    }
  }

  // Exact names first, then the names with a wildcard.
  for (final test in pending.where((test) => !test.hasWildcard)) {
    if (!remainingDart.remove(test.displayName)) {
      missing.add(test.displayName);
    }
  }
  for (final test in pending.where((test) => test.hasWildcard)) {
    final index = remainingDart.indexWhere(test.pattern.hasMatch);
    if (index < 0) {
      missing.add(test.displayName);
    } else {
      remainingDart.removeAt(index);
    }
  }

  // What is left in Dart must be explained by extras.md.
  final extra = <String>[];
  final wholeFile = extras.any((note) => note.test == wholeFileMarker);
  final usedExtras = <ParityNote>{};
  for (final name in remainingDart) {
    final note = extras.where((note) => note.test == name).firstOrNull;
    if (note != null) {
      usedExtras.add(note);
    } else if (!wholeFile) {
      extra.add(name);
    }
  }
  for (final note in extras) {
    if (note.test != wholeFileMarker && !usedExtras.contains(note)) {
      stale.add('${note.test} (not an extra test of $dartFile)');
    }
  }
  if (wholeFile && rnFile.isNotEmpty) {
    problems.add(
      'the extras entry "$wholeFileMarker" is for a Dart file with no React '
      'Native counterpart, and $dartFile has one ($rnFile)',
    );
  }

  return FileParity(
    rnFile: rnFile,
    dartFile: dartFile,
    rnCount: rn.length,
    dartCount: dart.length,
    dartFileExists: dart.isNotEmpty,
    missing: missing,
    extra: extra,
    excepted: excepted,
    staleExceptions: stale,
    problems: problems,
  );
}

/// The report as text: one line per file, the differences under it, and a
/// summary line.
String renderReport(ParityReport report) {
  final out = StringBuffer();
  for (final file in report.files) {
    final title = file.rnFile.isEmpty
        ? '${file.dartFile} (Dart only)'
        : '${file.rnFile} -> ${file.dartFile}';
    final covered = file.rnCount - file.missing.length - file.excepted.length;
    final expected = file.rnCount - file.excepted.length;
    final count = file.rnFile.isEmpty
        ? '${file.dartCount} extra'
        : '$covered/$expected';
    final exceptions = file.excepted.isEmpty
        ? ''
        : ' (+${file.excepted.length} excepted)';
    out.writeln('${file.ok ? 'ok  ' : 'FAIL'} $count$exceptions  $title');
    final untested =
        file.rnFile.isNotEmpty && !file.dartFileExists && file.rnCount > 0;
    if (untested) {
      out.writeln('       no Dart test in ${file.dartFile}');
    }
    for (final name in untested ? const <String>[] : file.missing) {
      out.writeln('       missing in Dart: $name');
    }
    for (final name in file.extra) {
      out.writeln('       extra in Dart (not in docs/parity/extras.md): $name');
    }
    for (final entry in file.staleExceptions) {
      out.writeln('       stale entry in docs/parity: $entry');
    }
    for (final problem in file.problems) {
      out.writeln('       $problem');
    }
  }
  final failing = report.files.where((file) => !file.ok).length;
  out.writeln(
    '${report.files.length} files, ${report.rnCount} React Native scenarios, '
    '${report.dartCount} Dart tests, $failing with differences.',
  );
  return out.toString();
}

/// The parity table of the use cases, in Markdown.
String renderUseCaseTable(ParityReport report) {
  final rows = [
    for (final file in report.files)
      if (file.rnFile.contains('/use-cases/')) file,
  ];
  final out = StringBuffer()
    ..writeln(
      '| Use case | React Native test file | Dart test file | '
      'RN tests | Dart tests | Status |',
    )
    ..writeln('| --- | --- | --- | ---: | ---: | --- |');
  var rnTotal = 0;
  var dartTotal = 0;
  for (final file in rows) {
    final name = p.posix.basename(file.rnFile).replaceFirst(rnTestSuffix, '');
    final excepted = file.excepted.isEmpty
        ? ''
        : ' (${file.excepted.length} excepted)';
    final status = file.ok
        ? 'identical$excepted'
        : !file.dartFileExists
        ? 'Dart file missing'
        : '${file.missing.length} missing, ${file.extra.length} extra';
    rnTotal += file.rnCount;
    dartTotal += file.dartCount;
    out.writeln(
      '| $name | `${file.rnFile}` | `${file.dartFile}` | ${file.rnCount} | '
      '${file.dartCount} | $status |',
    );
  }
  out.writeln('| **Total** | | | $rnTotal | $dartTotal | |');
  return out.toString();
}

/// The React Native test files under [rnRoot] (relative paths with `/`).
List<String> findRnTestFiles(Directory rnRoot) {
  final files = <String>[];
  for (final folder in rnTestFolders) {
    final directory = Directory(p.join(rnRoot.path, folder));
    if (!directory.existsSync()) {
      continue;
    }
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith(rnTestSuffix)) {
        files.add(
          p.posix.joinAll(p.split(p.relative(entity.path, from: rnRoot.path))),
        );
      }
    }
  }
  return files..sort();
}

/// The names that `jest --json` wrote, by test file relative to [rnRoot].
Map<String, List<TsTest>> readJestNames(String json, Directory rnRoot) {
  final decoded = jsonDecode(json) as Map<String, Object?>;
  final result = <String, List<TsTest>>{};
  for (final entry in decoded['testResults']! as List<Object?>) {
    final suite = entry! as Map<String, Object?>;
    final path = p.posix.joinAll(
      p.split(p.relative(suite['name']! as String, from: rnRoot.path)),
    );
    result[path] = [
      for (final item in suite['assertionResults']! as List<Object?>)
        _jestTest(item! as Map<String, Object?>),
    ];
  }
  return result;
}

TsTest _jestTest(Map<String, Object?> assertion) => TsTest([
  assertion['fullName']! as String,
], skipped: assertion['status'] == 'pending');

/// Runs `dart test` on the folders that hold tests and returns its JSON output.
typedef DartTestRunner = Future<String> Function(Directory root);

/// The pure Dart test folders of the project under [root] that hold a test,
/// relative to [root] with `/` separators: the domain and the application of
/// the core (`test/core/domain`, `test/core/application`) and of each feature
/// (`test/features/<feature>/domain`, `test/features/<feature>/application`),
/// the glue between features (`test/app/composition`) and the pure folders of
/// `test/support` (the fakes and their tests). They run under `dart test`; the
/// infrastructure, the rest of the app and the support that needs Flutter do
/// not.
List<String> pureTestFolders(Directory root) {
  final features = Directory(
    p.join(root.path, dartTestFolder, dartFeaturesFolder),
  );
  final featureNames = features.existsSync()
      ? [
          for (final entity in features.listSync())
            if (entity is Directory) p.basename(entity.path),
        ]
      : <String>[];
  final candidates = [
    for (final layer in parityLayers) '$dartTestFolder/$dartCoreFolder/$layer',
    for (final feature in featureNames..sort())
      for (final layer in parityLayers)
        '$dartTestFolder/$dartFeaturesFolder/$feature/$layer',
    '$dartTestFolder/$dartCompositionFolder',
    for (final folder in pureSupportFolders)
      '$dartTestFolder/$dartSupportFolder/$folder',
  ];
  return [
    for (final folder in candidates)
      if (_hasDartTests(
        Directory(p.joinAll([root.path, ...folder.split('/')])),
      ))
        folder,
  ];
}

/// The Dart test files (`*_test.dart`) in [folders], relative to [root] with
/// `/` separators, sorted.
List<String> dartTestFilesIn(Directory root, Iterable<String> folders) {
  final files = <String>[];
  for (final folder in folders) {
    final directory = Directory(p.joinAll([root.path, ...folder.split('/')]));
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith(dartTestSuffix)) {
        files.add(
          p.posix.joinAll(p.split(p.relative(entity.path, from: root.path))),
        );
      }
    }
  }
  return files..sort();
}

/// The default [DartTestRunner]: `dart test` on the pure test folders, with the
/// JSON reporter (see [pureTestFolders]).
Future<String> runDartTest(Directory root) async {
  final folders = pureTestFolders(root);
  if (folders.isEmpty) {
    return '';
  }
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['test', ...folders, '--reporter', 'json'],
    workingDirectory: root.path,
    stdoutEncoding: utf8,
  );
  return result.stdout as String;
}

bool _hasDartTests(Directory directory) =>
    directory.existsSync() &&
    directory
        .listSync(recursive: true)
        .any(
          (entity) => entity is File && entity.path.endsWith(dartTestSuffix),
        );

const String _usage = '''
Usage: dart run tool/scenario_parity.dart --rn <react-native-repo> [options]

  --rn <path>          the checkout of the React Native repository (required)
  --only <prefix>      only the React Native test files under the prefix, for
                       example src/domain/shared (repeatable)
  --table              print the parity table of the use cases (Markdown)
  --rn-names <file>    read the React Native names from `jest --json` output
  --dart-names <file>  read the Dart names from `dart test --reporter json`
  --root <path>        the Flutter project (default: the current directory)

The Dart tests are those of the pure folders: test/core/{domain,application},
test/features/*/{domain,application}, test/app/composition and
test/support/{builders,contracts,fakes}.
''';

/// The command line, with the output streams and the runner of `dart test`
/// given, so that it can be tested. Returns the exit code.
Future<int> runScenarioParity(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  DartTestRunner runner = runDartTest,
}) async {
  String? rn;
  String? rnNames;
  String? dartNames;
  var root = '.';
  var table = false;
  final only = <String>[];
  for (var index = 0; index < args.length; index++) {
    String value() {
      if (index + 1 >= args.length) {
        throw FormatException('${args[index]} needs a value');
      }
      return args[++index];
    }

    try {
      switch (args[index]) {
        case '--rn':
          rn = value();
        case '--only':
          only.add(value());
        case '--table':
          table = true;
        case '--rn-names':
          rnNames = value();
        case '--dart-names':
          dartNames = value();
        case '--root':
          root = value();
        case '-h' || '--help':
          out.write(_usage);
          return 0;
        default:
          throw FormatException('unknown option ${args[index]}');
      }
    } on FormatException catch (error) {
      err
        ..writeln(error.message)
        ..write(_usage);
      return 2;
    }
  }
  if (rn == null) {
    err
      ..writeln('--rn is required')
      ..write(_usage);
    return 2;
  }
  final rnRoot = Directory(rn);
  if (!Directory(p.join(rnRoot.path, 'src')).existsSync()) {
    err.writeln(
      '${rnRoot.path} is not a checkout of the React Native repository',
    );
    return 2;
  }
  final projectRoot = Directory(root);

  // The React Native side.
  final rnTests = <String, List<TsTest>>{};
  if (rnNames != null) {
    final all = readJestNames(File(rnNames).readAsStringSync(), rnRoot);
    rnTests.addAll({
      for (final MapEntry(:key, :value) in all.entries)
        if (parityLayerOf(key) != null) key: value,
    });
  } else {
    for (final file in findRnTestFiles(rnRoot)) {
      if (only.isNotEmpty && !only.any(file.startsWith)) {
        continue;
      }
      rnTests[file] = extractTsTests(file, root: rnRoot);
    }
  }

  // The Dart side.
  final output = dartNames != null
      ? File(dartNames).readAsStringSync()
      : await runner(projectRoot);
  final dart = parseDartTestEvents(output, root: projectRoot.absolute.path);

  List<ParityNote> notes(String path) {
    final file = File(p.join(projectRoot.path, path));
    return file.existsSync() ? parseParityNotes(file.readAsStringSync()) : [];
  }

  // The Dart test files that can stand for a React Native one: those on disk
  // and those that dart test reported.
  final dartTestFiles = {
    ...dartTestFilesIn(projectRoot, pureTestFolders(projectRoot)),
    ...dart.tests.keys,
    ...dart.loadErrors,
  };

  final ParityReport report;
  try {
    report = compareScenarios(
      rnTests: rnTests,
      dartTests: dart.tests,
      exceptions: notes(exceptionsFile),
      extras: notes(extrasFile),
      only: only,
      dartLoadErrors: dart.loadErrors.toSet(),
      dartTestFiles: dartTestFiles,
    );
  } on FormatException catch (error) {
    err.writeln(error.message);
    return 2;
  }
  out.write(table ? renderUseCaseTable(report) : renderReport(report));
  if (dart.loadErrors.isNotEmpty) {
    err.writeln(
      'Dart test files that did not load: ${dart.loadErrors.join(', ')}',
    );
  }
  return report.ok ? 0 : 1;
}

Future<void> main(List<String> args) async {
  exitCode = await runScenarioParity(args, out: stdout, err: stderr);
}
