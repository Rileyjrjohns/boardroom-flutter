// Checks the import rules of the hexagonal layers.
//
// The code of lib/ is organised feature first: lib/core is the shared kernel,
// lib/features/<feature> holds one folder per feature, and lib/app is the
// composition (the app itself, the persistence of the whole file, the simulated
// world of the development build). Inside core and inside each feature, the
// folders are the layers (domain, application, infrastructure, presentation).
// Dependencies point inward: the domain imports nothing but domain code, the
// application imports the domain, the adapters implement the ports, the UI
// never reaches an adapter, and only app/ and main.dart know them all. Nothing
// in the compiler enforces that, so this script does: it reads every import,
// export and part directive of lib/ and test/ with the Dart parser (no regular
// expressions, so comments, strings, multi-line directives and conditional
// imports cannot fool it) and fails when a file steps outside its layer.
//
// The rules are about layers only: an import counts by the layer of its target,
// whatever the feature or core it sits in. Which feature may depend on which
// other one is not checked here (yet).
//
// Usage: dart run tool/check_imports.dart [project-root]
// Exit code 0 when every rule holds, 1 with one line per violation otherwise.
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

/// Name of this package: `package:boardroom/...` URIs point inside lib/.
const String projectPackage = 'boardroom';

/// Source folder, made of the shared kernel, the features and the composition.
const String libFolder = 'lib';

/// Test folder, scanned for the layers that must run without Flutter.
const String testFolder = 'test';

/// Folder of lib/ (and of test/) that holds the shared kernel.
const String coreFolder = 'core';

/// Folder of lib/ (and of test/) that holds one folder per feature.
const String featuresFolder = 'features';

/// Folder of lib/ that holds the composition, and name of its layer: the one
/// place that knows every other layer.
const String appFolder = 'app';

/// Folder of test/ that holds the helpers shared by the tests (builders, fakes,
/// contract suites...).
const String supportFolder = 'support';

/// The entry point may wire everything together, so it is exempt from the layer
/// rules.
const String entryPointFile = 'lib/main.dart';

/// Folder of the ARB files and of the generated localization code.
const String l10nFolder = 'lib/l10n';

/// Start of the file names that `flutter gen-l10n` writes in [l10nFolder]
/// (`app_localizations.dart`, `app_localizations_en.dart`...). Only these are
/// exempt like the entry point, because a tool writes them, not a person, and
/// they are gitignored. Any other Dart file of the folder is hand-written, so
/// it belongs to no layer and is refused: otherwise it could import an adapter
/// and hand it to the UI through the exempt folder.
const String generatedL10nPrefix = 'lib/l10n/app_localizations';

/// Pseudo layer name for lib/main.dart.
const String _entryLayer = 'entry';

/// Pseudo layer name for lib/l10n.
const String _l10nLayer = 'l10n';

/// Pseudo layer name for a file of lib/ that belongs to no layer. As a key of
/// [LayerRule.whyNotLayer] it is also the default reason.
const String _unknownLayer = 'unknown';

/// Pseudo layer name for a file of test/.
const String _testLayer = 'test';

/// The layers a folder of core, or of a feature, is made of. A Dart file of
/// lib/core or lib/features that is not in one of them is outside the layers.
const Set<String> areaLayers = {
  'domain',
  'application',
  'infrastructure',
  'presentation',
};

/// `dart:` libraries that exist on every Dart platform and do no I/O. dart:io,
/// dart:ui, dart:isolate, dart:ffi and dart:html tie code to a platform, so the
/// pure layers cannot use them.
const Set<String> pureDartLibraries = {
  'core',
  'async',
  'collection',
  'math',
  'typed_data',
  'convert',
};

/// Packages the pure layers (domain, application) may use. To extend the list,
/// add the package with a comment saying why it carries no framework or I/O.
const Set<String> purePackages = {
  // Annotations such as @immutable: no runtime behavior.
  'meta',
  // Collection helpers (equality, queues) written in pure Dart.
  'collection',
  // Annotations read by the freezed code generator, no framework behind them.
  'freezed_annotation',
  // Annotations read by the json_serializable code generator.
  'json_annotation',
};

/// Packages that belong to the adapters (HTTP, database, secure storage,
/// biometrics, connectivity, the folders of the device, the native screen
/// protection plugin). Only infrastructure and app use them: a screen that
/// imports one skips the ports. A package named here also covers its federated
/// parts (`local_auth_android`, `drift_flutter`...), matched on the `<name>_`
/// prefix.
const Set<String> adapterPackages = {
  'connectivity_plus',
  'dio',
  'drift',
  'flutter_secure_storage',
  'local_auth',
  'path_provider',
  'screen_protection',
  'sqlite3',
};

/// Packages that the pure tests add to the rules of their layer: the test
/// runner itself. package:flutter_test is deliberately absent, so these tests
/// run with plain `dart test`.
const Set<String> pureTestPackages = {'test'};

/// The imports of infrastructure code that reach into lib/app, which the layer
/// rules refuse, listed until they are removed: the key is the importing file,
/// the value the files of lib/app it imports. They are the adapters and the
/// opening of the database, which are written against the concrete database of
/// the whole file (`BoardroomDatabase`) that lives in lib/app/persistence.
///
/// This table is temporary. The imports it lists are removed when the database
/// is split per feature, and the entries with them. An entry whose file no
/// longer has the import is itself a violation, so the table cannot outlive the
/// debt it records.
const Map<String, Set<String>> temporaryExemptions = {
  'lib/core/infrastructure/persistence/migrate.dart': {
    'lib/app/persistence/migrations.dart',
  },
  'lib/core/infrastructure/persistence/protected_database.dart': {
    'lib/app/persistence/boardroom_database.dart',
    'lib/app/persistence/migrations.dart',
  },
  'lib/features/documents/infrastructure/drift_document_cache.dart': {
    'lib/app/persistence/boardroom_database.dart',
    'lib/app/persistence/schema.dart',
  },
  'lib/features/meetings/infrastructure/drift_meeting_cache.dart': {
    'lib/app/persistence/boardroom_database.dart',
    'lib/app/persistence/schema.dart',
  },
  'lib/features/votes/infrastructure/drift_vote_outbox.dart': {
    'lib/app/persistence/boardroom_database.dart',
    'lib/app/persistence/schema.dart',
  },
};

/// What one layer is allowed to import, and the reasons given when it is not.
class LayerRule {
  /// Creates the rule of a layer.
  const new({
    required this.label,
    required this.allowedLayers,
    required this.whyNotLayer,
    this.allowL10n = false,
    this.dartLibraries,
    this.packages,
    this.deniedPackages = const {},
    this.allowedTestScopes = const {},
  });

  /// Name used in the messages, for example `domain` or `test/core/domain`.
  final String label;

  /// Layers of lib/ this layer may import (itself included), whatever the
  /// core or the feature they sit in.
  final Set<String> allowedLayers;

  /// Why an import of another layer of the project is refused, by layer name.
  /// The key [_unknownLayer] is the default reason.
  final Map<String, String> whyNotLayer;

  /// Whether the generated localization code of lib/l10n may be imported.
  final bool allowL10n;

  /// Allowed `dart:` libraries, or null when any is allowed.
  final Set<String>? dartLibraries;

  /// Allowed packages, or null when any is allowed. The project itself is
  /// covered by [allowedLayers].
  final Set<String>? packages;

  /// Packages refused even though [packages] is null (any package allowed),
  /// with their federated parts. Used by the layers that must reach adapters
  /// through the ports, never through their packages.
  final Set<String> deniedPackages;

  /// Folders under test/ (project-relative, without a trailing `/`) whose files
  /// this rule may import. Empty for the layers of lib/.
  final Set<String> allowedTestScopes;
}

/// The rules of the five layers.
///
/// A layer is the folder under `lib/core/`, under `lib/features/<feature>/` or,
/// for the composition, `lib/app` itself. Dependencies point inward, so the
/// layers closer to the center know nothing about the outer ones. The rules
/// look at the layer of the target only, not at the core or the feature it
/// belongs to.
const Map<String, LayerRule> layerRules = {
  // The business rules: they must outlive any framework, so they run with
  // `dart test` alone.
  'domain': LayerRule(
    label: 'domain',
    allowedLayers: {'domain'},
    whyNotLayer: {
      _unknownLayer:
          'the domain is the innermost layer and depends on nothing else',
    },
    dartLibraries: pureDartLibraries,
    packages: purePackages,
  ),
  // Use cases orchestrate the domain through ports. The adapters that implement
  // those ports are injected, never imported.
  'application': LayerRule(
    label: 'application',
    allowedLayers: {'domain', 'application'},
    whyNotLayer: {
      _unknownLayer:
          'use cases depend on the domain and reach adapters through ports',
    },
    dartLibraries: pureDartLibraries,
    packages: purePackages,
  ),
  // Adapters implement the ports of the domain and application, with any
  // platform library. They cannot know the UI nor the composition that builds
  // them.
  'infrastructure': LayerRule(
    label: 'infrastructure',
    allowedLayers: {'domain', 'application', 'infrastructure'},
    whyNotLayer: {
      'presentation': 'an adapter must not depend on the UI',
      appFolder: 'an adapter must not depend on the composition that builds it',
      _unknownLayer: 'an adapter depends on the domain and application only',
    },
  ),
  // Screens and notifiers drive the use cases through ports. They never build
  // or import an adapter themselves, nor the package behind one. They may use
  // the generated localizations.
  'presentation': LayerRule(
    label: 'presentation',
    allowedLayers: {'domain', 'application', 'presentation'},
    allowL10n: true,
    deniedPackages: adapterPackages,
    whyNotLayer: {
      'infrastructure':
          'the UI never imports an adapter, it gets the ports from the '
          'composition in app',
      appFolder: 'the composition imports the UI, not the other way round',
      _unknownLayer: 'the UI depends on the domain and application only',
    },
  ),
  // The composition: the only place that knows every layer, so it chooses which
  // adapter stands behind each port. It may use any package.
  appFolder: LayerRule(
    label: appFolder,
    allowedLayers: {
      'domain',
      'application',
      'infrastructure',
      'presentation',
      appFolder,
    },
    allowL10n: true,
    whyNotLayer: {},
  ),
};

/// Layers of the test folders that follow the rules of the layer of the same
/// name, so they run under plain `dart test`. The other test folders
/// (infrastructure, app, tool...) are free: they need Flutter or real adapters.
const Set<String> pureTestLayers = {'domain', 'application'};

/// The folders of test/support that are pure, with the layer whose rules they
/// follow. The others (infrastructure...) are free.
const Map<String, String> pureSupportLayers = {
  'builders': 'domain',
  'contracts': 'application',
  'fakes': 'application',
};

/// Folders of test/support that a pure test may import, by layer of the test:
/// the same layer and the layers below it (a domain test never needs a fake of
/// a port).
const Map<String, Set<String>> pureTestSupport = {
  'domain': {'builders'},
  'application': {'builders', 'contracts', 'fakes'},
};

/// One broken rule.
class Violation {
  /// Creates a violation found at [path]:[line].
  const new({required this.path, required this.line, required this.message});

  /// Path of the file, relative to the project root, with `/` separators.
  final String path;

  /// 1-based line of the directive (or of the URI inside it).
  final int line;

  /// What is wrong: `<layer> may not import <uri> (<reason>)`, or a placement
  /// or parsing message.
  final String message;

  @override
  String toString() => '$path:$line: $message';
}

/// Outcome of a check.
class CheckResult {
  /// Creates the outcome of a check over [filesChecked] files.
  const new({required this.violations, required this.filesChecked});

  /// Every violation, ordered by path then line.
  final List<Violation> violations;

  /// Number of Dart files that were read (exempt and free files excluded).
  final int filesChecked;
}

/// A directive URI with the line it is written on.
class _UriRef {
  const new(this.value, this.line);

  final String value;
  final int line;
}

/// Where a URI points, once resolved. Exactly one kind of field is set.
class _Target {
  const new dartLibrary(this.dartLibrary)
    : package = null,
      layer = null,
      path = null,
      problem = null;

  const new package(this.package)
    : dartLibrary = null,
      layer = null,
      path = null,
      problem = null;

  const new project(this.layer, this.path)
    : dartLibrary = null,
      package = null,
      problem = null;

  const new unresolved(this.problem)
    : dartLibrary = null,
      package = null,
      layer = null,
      path = null;

  /// Name of the `dart:` library, for example `io`.
  final String? dartLibrary;

  /// Name of the external package.
  final String? package;

  /// Layer of a file of the project: a key of [layerRules] or a pseudo layer.
  final String? layer;

  /// Project-relative path of a file of the project.
  final String? path;

  /// Why the URI could not be resolved.
  final String? problem;
}

/// Checks every Dart file of lib/ and test/ under [root] and returns the
/// violations. [exemptions] lists the imports that the layer rules refuse but
/// that are tolerated for now (see [temporaryExemptions]).
CheckResult checkImports(
  Directory root, {
  Map<String, Set<String>> exemptions = temporaryExemptions,
}) {
  final violations = <Violation>[];
  var filesChecked = 0;

  for (final relative in _dartFiles(root)) {
    final inLib = relative.startsWith('$libFolder/');
    final LayerRule? rule;
    if (inLib) {
      final layer = _layerOfLibFile(relative);
      if (layer == _entryLayer || layer == _l10nLayer) {
        continue;
      }
      rule = layerRules[layer];
      if (rule == null) {
        // Not main.dart, not l10n, not a layer folder: the file belongs
        // nowhere.
        filesChecked++;
        violations.add(
          Violation(
            path: relative,
            line: 1,
            message:
                'file outside the layers (every file of lib/ lives in '
                '$coreFolder/<layer>, $featuresFolder/<feature>/<layer> or '
                '$appFolder, with <layer> one of: ${areaLayers.join(', ')}; '
                'only $entryPointFile and the files generated by gen-l10n in '
                '$l10nFolder are exempt)',
          ),
        );
        continue;
      }
    } else {
      rule = _pureTestRule(relative);
      if (rule == null) {
        // A free test folder.
        continue;
      }
    }

    filesChecked++;
    final source = File(p.joinAll([root.path, ...relative.split('/')]))
        .readAsStringSync();
    final parsed = parseString(
      content: source,
      path: relative,
      throwIfDiagnostics: false,
    );
    if (parsed.errors.isNotEmpty) {
      // A file that does not parse cannot be checked: fail instead of guessing.
      final offset = parsed.errors.first.offset;
      violations.add(
        Violation(
          path: relative,
          line: parsed.lineInfo.getLocation(offset).lineNumber,
          message: 'file does not parse, its imports cannot be checked',
        ),
      );
      continue;
    }

    final exempted = exemptions[relative] ?? const <String>{};
    final used = <String>{};
    for (final ref in _directiveUris(parsed)) {
      final target = _resolve(ref.value, relative);
      final reason = _denial(rule, target);
      if (reason == null) {
        continue;
      }
      final targetPath = target.path;
      if (targetPath != null && exempted.contains(targetPath)) {
        used.add(targetPath);
        continue;
      }
      violations.add(
        Violation(
          path: relative,
          line: ref.line,
          message: '${rule.label} may not import ${ref.value} ($reason)',
        ),
      );
    }
    for (final target in exempted.difference(used)) {
      violations.add(
        Violation(
          path: relative,
          line: 1,
          message:
              'stale exemption: the file no longer imports $target, remove '
              'the entry from temporaryExemptions',
        ),
      );
    }
  }

  violations.sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    return byPath != 0 ? byPath : a.line.compareTo(b.line);
  });
  return CheckResult(violations: violations, filesChecked: filesChecked);
}

/// Project-relative paths (with `/`) of the Dart files of lib/ and test/,
/// sorted.
List<String> _dartFiles(Directory root) {
  final files = <String>[];
  for (final folder in const [libFolder, testFolder]) {
    final directory = Directory(p.join(root.path, folder));
    if (!directory.existsSync()) {
      continue;
    }
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final relative = p.relative(entity.path, from: root.path);
        files.add(p.posix.joinAll(p.split(relative)));
      }
    }
  }
  return files..sort();
}

/// The layer of a file of lib/: a key of [layerRules] or a pseudo layer.
///
/// - `lib/app/<file...>` is the composition;
/// - `lib/core/<layer>/<file...>` and
///   `lib/features/<feature>/<layer>/<file...>` are in the layer written in
///   their path;
/// - anything else is [_unknownLayer].
String _layerOfLibFile(String relative) {
  if (relative == entryPointFile) {
    return _entryLayer;
  }
  if (_isGeneratedL10n(relative)) {
    return _l10nLayer;
  }
  final segments = relative.split('/');
  // A file directly under lib/ has only two segments.
  if (segments.length >= 3 && segments[1] == appFolder) {
    return appFolder;
  }
  if (segments.length >= 4 &&
      segments[1] == coreFolder &&
      areaLayers.contains(segments[2])) {
    return segments[2];
  }
  if (segments.length >= 5 &&
      segments[1] == featuresFolder &&
      areaLayers.contains(segments[3])) {
    return segments[3];
  }
  return _unknownLayer;
}

/// Whether [relative] is a file written by `flutter gen-l10n`.
bool _isGeneratedL10n(String relative) =>
    relative.startsWith(generatedL10nPrefix) &&
    relative.endsWith('.dart') &&
    !relative.substring(generatedL10nPrefix.length).contains('/');

/// The rule of a file under test/ that has to run without Flutter, or null when
/// its folder is free.
///
/// Three kinds of folder are pure, and follow the rules of one layer:
/// `test/core/<layer>`, `test/features/<feature>/<layer>` (the layer is the
/// folder, `domain` or `application`) and the pure folders of `test/support`
/// ([pureSupportLayers]). Such a file may import the lib code of its layer and
/// of the layers below it, the support folders of [pureTestSupport], and the
/// files of its own folder.
LayerRule? _pureTestRule(String relative) {
  final segments = relative.split('/');
  final String layer;
  final int depth;
  if (segments.length >= 4 &&
      segments[1] == coreFolder &&
      pureTestLayers.contains(segments[2])) {
    layer = segments[2];
    depth = 3;
  } else if (segments.length >= 5 &&
      segments[1] == featuresFolder &&
      pureTestLayers.contains(segments[3])) {
    layer = segments[3];
    depth = 4;
  } else if (segments.length >= 4 &&
      segments[1] == supportFolder &&
      pureSupportLayers.containsKey(segments[2])) {
    layer = pureSupportLayers[segments[2]]!;
    depth = 3;
  } else {
    return null;
  }
  final base = layerRules[layer]!;
  final folder = segments.take(depth).join('/');
  return LayerRule(
    label: folder,
    allowedLayers: base.allowedLayers,
    whyNotLayer: base.whyNotLayer,
    dartLibraries: base.dartLibraries,
    packages: {...?base.packages, ...pureTestPackages},
    deniedPackages: base.deniedPackages,
    allowedTestScopes: {
      folder,
      for (final name in pureTestSupport[layer]!)
        '$testFolder/$supportFolder/$name',
    },
  );
}

/// Every URI written in an import, export or part directive, the alternatives
/// of a conditional directive included.
List<_UriRef> _directiveUris(ParseStringResult parsed) {
  final refs = <_UriRef>[];
  void add(StringLiteral? literal) {
    if (literal == null) {
      return;
    }
    // An interpolated URI is not valid Dart; its value is then empty and the
    // directive is reported as unresolvable.
    refs.add(
      _UriRef(
        literal.stringValue ?? '',
        parsed.lineInfo.getLocation(literal.offset).lineNumber,
      ),
    );
  }

  for (final directive in parsed.unit.directives) {
    switch (directive) {
      case final NamespaceDirective namespace:
        add(namespace.uri);
        for (final configuration in namespace.configurations) {
          add(configuration.uri);
        }
      case final PartDirective part:
        add(part.uri);
      case final PartOfDirective partOf:
        add(partOf.uri);
      default:
        break;
    }
  }
  return refs;
}

/// Resolves [uri], written in the project file [from], to where it points.
_Target _resolve(String uri, String from) {
  final Uri parsed;
  try {
    parsed = Uri.parse(uri);
  } on FormatException {
    return const _Target.unresolved('the URI is not valid');
  }
  switch (parsed.scheme) {
    case 'dart':
      return _Target.dartLibrary(parsed.path.split('/').first);
    case 'package':
      final segments = parsed.pathSegments;
      if (segments.isEmpty || segments.first.isEmpty) {
        return const _Target.unresolved('the package URI is not valid');
      }
      if (segments.first != projectPackage) {
        return _Target.package(segments.first);
      }
      return _projectTarget(p.posix.joinAll([libFolder, ...segments.skip(1)]));
    case '':
      if (parsed.path.isEmpty || parsed.path.startsWith('/')) {
        return const _Target.unresolved('absolute paths cannot be checked');
      }
      final joined = p.posix.join(p.posix.dirname(from), parsed.path);
      final resolved = p.posix.normalize(joined);
      if (resolved == '..' || resolved.startsWith('../')) {
        return const _Target.unresolved('the file is outside the project');
      }
      return _projectTarget(resolved);
    default:
      return _Target.unresolved(
        'the ${parsed.scheme}: scheme cannot be checked',
      );
  }
}

/// Classifies a project-relative path.
_Target _projectTarget(String path) {
  if (path.startsWith('$testFolder/')) {
    return _Target.project(_testLayer, path);
  }
  if (!path.startsWith('$libFolder/')) {
    return const _Target.unresolved('the file is outside lib/ and test/');
  }
  return _Target.project(_layerOfLibFile(path), path);
}

/// Why [rule] refuses [target], or null when the import is allowed.
String? _denial(LayerRule rule, _Target target) {
  final problem = target.problem;
  if (problem != null) {
    return problem;
  }

  final dartLibrary = target.dartLibrary;
  if (dartLibrary != null) {
    final allowed = rule.dartLibraries;
    if (allowed == null || allowed.contains(dartLibrary)) {
      return null;
    }
    final names = (allowed.toList()..sort()).map((name) => 'dart:$name');
    return 'dart:$dartLibrary is tied to a platform; '
        'allowed: ${names.join(', ')}';
  }

  final package = target.package;
  if (package != null) {
    final adapter = rule.deniedPackages.where(
      (name) => package == name || package.startsWith('${name}_'),
    );
    if (adapter.isNotEmpty) {
      return 'package:$package belongs to the adapters; use it in '
          'infrastructure and reach it through a port';
    }
    final allowed = rule.packages;
    if (allowed == null || allowed.contains(package)) {
      return null;
    }
    final names = (allowed.toList()..sort()).join(', ');
    return package.startsWith('flutter')
        ? 'Flutter is not allowed here, this code runs with plain '
              '`dart test`; allowed packages: $names'
        : 'package:$package is not in the allowlist; '
              'allowed packages: $names';
  }

  final layer = target.layer;
  if (layer == _testLayer) {
    // Only the files of the test folders the rule lists.
    final path = target.path;
    if (path != null &&
        rule.allowedTestScopes.any((scope) => path.startsWith('$scope/'))) {
      return null;
    }
    if (rule.allowedTestScopes.isEmpty) {
      return 'production code never imports test code';
    }
    final scopes = rule.allowedTestScopes.toList()..sort();
    return 'test support is limited to ${scopes.join(', ')}';
  }
  if (layer == null || rule.allowedLayers.contains(layer)) {
    return null;
  }
  if (layer == _l10nLayer && rule.allowL10n) {
    return null;
  }
  return switch (layer) {
    _entryLayer => 'nothing imports the entry point',
    _l10nLayer => 'only the UI uses the generated localizations',
    _unknownLayer => 'the file belongs to no layer',
    _ =>
      rule.whyNotLayer[layer] ??
          rule.whyNotLayer[_unknownLayer] ??
          'this layer is not allowed',
  };
}

/// Prints the outcome of a check on [out] and returns the process exit code.
int report(CheckResult result, StringSink out) {
  if (result.violations.isEmpty) {
    out.writeln(
      'Import rules OK: ${result.filesChecked} files checked, no violation.',
    );
    return 0;
  }
  result.violations.forEach(out.writeln);
  return 1;
}

void main(List<String> args) {
  final root = Directory(args.isEmpty ? '.' : args.first);
  if (!root.existsSync()) {
    stderr.writeln('Project root not found: ${root.path}');
    exit(2);
  }
  exit(report(checkImports(root), stdout));
}
