// Checks the import rules of the hexagonal layers.
//
// The folders under lib/ are the layers. Dependencies point inward: the domain
// imports nothing of the project, the application imports the domain, the
// adapters implement the ports, and the UI reaches the adapters only through
// the providers of di. Nothing in the compiler enforces that, so this script
// does: it reads every import, export and part directive of lib/ and test/ with
// the Dart parser (no regular expressions, so comments, strings, multi-line
// directives and conditional imports cannot fool it) and fails when a file
// steps outside its layer.
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

/// Source folder whose first-level folders are the layers.
const String libFolder = 'lib';

/// Test folder, scanned for the layers that must run without Flutter.
const String testFolder = 'test';

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
/// biometrics, the native screen protection plugin). Only infrastructure uses
/// them: a screen or a provider that imports one skips the ports. A package
/// named here also covers its federated parts (`local_auth_android`,
/// `drift_flutter`...), matched on the `<name>_` prefix.
const Set<String> adapterPackages = {
  'dio',
  'drift',
  'flutter_secure_storage',
  'local_auth',
  'screen_protection',
  'sqlite3',
};

/// Packages that test/domain and test/application add to the rules of their
/// layer: the test runner itself. package:flutter_test is deliberately absent,
/// so these tests run with plain `dart test`.
const Set<String> pureTestPackages = {'test'};

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
    this.allowedTestFolders = const {},
  });

  /// Name used in the messages, for example `domain` or `test/domain`.
  final String label;

  /// Layers of lib/ this layer may import (itself included).
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
  /// through the project's own infrastructure, never through its packages.
  final Set<String> deniedPackages;

  /// Folders under test/ whose support files this rule may import. Empty for
  /// the layers of lib/.
  final Set<String> allowedTestFolders;
}

/// The rules of the five layers.
///
/// A layer is the first folder under lib/. Dependencies point inward, so the
/// layers closer to the center know nothing about the outer ones.
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
  // platform library. They cannot know the UI nor the wiring that builds them.
  'infrastructure': LayerRule(
    label: 'infrastructure',
    allowedLayers: {'domain', 'application', 'infrastructure'},
    whyNotLayer: {
      'presentation': 'an adapter must not depend on the UI',
      'di': 'an adapter must not depend on the wiring that builds it',
      _unknownLayer: 'an adapter depends on the domain and application only',
    },
  ),
  // Screens and notifiers read ports through the providers of di. They never
  // build or import an adapter themselves, nor the package behind one. They may
  // use the generated localizations.
  'presentation': LayerRule(
    label: 'presentation',
    allowedLayers: {'domain', 'application', 'presentation', 'di'},
    allowL10n: true,
    deniedPackages: adapterPackages,
    whyNotLayer: {
      'infrastructure':
          'the UI reaches adapters through the providers of di, never directly',
      _unknownLayer: 'the UI depends on the domain, application and di only',
    },
  ),
  // The composition root: the only place that knows both the ports and their
  // adapters, through the classes of infrastructure (the adapter packages stay
  // inside infrastructure).
  'di': LayerRule(
    label: 'di',
    allowedLayers: {'domain', 'application', 'infrastructure', 'di'},
    deniedPackages: adapterPackages,
    whyNotLayer: {
      'presentation': 'the wiring must not depend on the UI that consumes it',
      _unknownLayer:
          'the wiring depends on the domain, application and infrastructure '
          'only',
    },
  ),
};

/// Test folders that follow the rules of the layer of the same name, so they
/// run under plain `dart test`. The other test folders (presentation,
/// infrastructure, di, tool...) are free: they need Flutter or real adapters.
const Set<String> pureTestLayers = {'domain', 'application'};

/// Test folders whose support files a pure test may import, by test folder:
/// the same layer and the layers below it (a domain test never needs an
/// application helper).
const Map<String, Set<String>> pureTestSupport = {
  'domain': {'domain'},
  'application': {'domain', 'application'},
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
/// violations.
CheckResult checkImports(Directory root) {
  final violations = <Violation>[];
  var filesChecked = 0;

  for (final relative in _dartFiles(root)) {
    final inLib = relative.startsWith('$libFolder/');
    final layer = inLib ? _layerOfLibFile(relative) : _testLayerOf(relative);
    if (layer == _entryLayer || layer == _l10nLayer) {
      continue;
    }

    final rule = layer == null ? null : _ruleFor(relative, layer);
    if (rule == null) {
      if (inLib) {
        // Not main.dart, not l10n, not a layer folder: the file belongs
        // nowhere.
        filesChecked++;
        violations.add(
          Violation(
            path: relative,
            line: 1,
            message:
                'file outside the layers (every file of lib/ lives in one '
                'of: ${layerRules.keys.join(', ')}; only $entryPointFile and '
                'the files generated by gen-l10n in $l10nFolder are exempt)',
          ),
        );
      }
      // Otherwise a free test folder.
      continue;
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

    for (final ref in _directiveUris(parsed)) {
      final reason = _denial(rule, _resolve(ref.value, relative));
      if (reason != null) {
        violations.add(
          Violation(
            path: relative,
            line: ref.line,
            message: '${rule.label} may not import ${ref.value} ($reason)',
          ),
        );
      }
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
String _layerOfLibFile(String relative) {
  if (relative == entryPointFile) {
    return _entryLayer;
  }
  if (_isGeneratedL10n(relative)) {
    return _l10nLayer;
  }
  final segments = relative.split('/');
  // lib/<layer>/<file...>: a file directly under lib/ has only two segments.
  if (segments.length >= 3 && layerRules.containsKey(segments[1])) {
    return segments[1];
  }
  return _unknownLayer;
}

/// Whether [relative] is a file written by `flutter gen-l10n`.
bool _isGeneratedL10n(String relative) =>
    relative.startsWith(generatedL10nPrefix) &&
    relative.endsWith('.dart') &&
    !relative.substring(generatedL10nPrefix.length).contains('/');

/// The layer (`domain`, `application`) whose rules a file under test/ follows,
/// or null when its folder is free.
String? _testLayerOf(String relative) {
  final segments = relative.split('/');
  if (segments.length >= 3 && pureTestLayers.contains(segments[1])) {
    return segments[1];
  }
  return null;
}

/// The rule that applies to [relative], or null when no layer claims it.
LayerRule? _ruleFor(String relative, String layer) {
  final base = layerRules[layer];
  if (base == null || relative.startsWith('$libFolder/')) {
    return base;
  }
  return LayerRule(
    label: '$testFolder/$layer',
    allowedLayers: base.allowedLayers,
    whyNotLayer: base.whyNotLayer,
    dartLibraries: base.dartLibraries,
    packages: {...?base.packages, ...pureTestPackages},
    deniedPackages: base.deniedPackages,
    allowedTestFolders: pureTestSupport[layer] ?? const {},
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
    // test/<folder>/...: only the support files of the folders the rule lists.
    final folder = target.path?.split('/').elementAtOrNull(1);
    if (folder != null && rule.allowedTestFolders.contains(folder)) {
      return null;
    }
    if (rule.allowedTestFolders.isEmpty) {
      return 'production code never imports test code';
    }
    final folders = (rule.allowedTestFolders.toList()..sort()).map(
      (name) => '$testFolder/$name',
    );
    return 'test support is limited to ${folders.join(', ')}';
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
