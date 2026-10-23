import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/check_imports.dart';

// Pure Dart: these tests build small throwaway projects in a temp folder and
// run the checker on them, so every rule is exercised in both directions
// (allowed passes, forbidden fails on the right line) without touching the real
// tree. The last tests run the checker and the real script on the real repo.

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('check_imports_test_');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  /// Writes [content] to the project-relative [path] of the throwaway project.
  void write(String path, String content) {
    File(p.joinAll([root.path, ...path.split('/')]))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// The violations as `path:line` strings, to assert where each is reported.
  List<String> violationsAt() => [
    for (final v in checkImports(root).violations) '${v.path}:${v.line}',
  ];

  List<String> messages() => [
    for (final v in checkImports(root).violations) v.toString(),
  ];

  group('domain', () {
    test(
      'may import itself, pure dart: libraries and allowlisted packages',
      () {
        write('lib/domain/a.dart', '');
        write('lib/domain/sub/b.dart', '''
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:core';
import 'dart:math';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';
import 'package:boardroom/domain/a.dart';
import '../a.dart';
import 'b.dart';
export 'package:boardroom/domain/a.dart';
part 'b.g.dart';
''');
        write('lib/domain/sub/b.g.dart', "part of 'b.dart';\n");

        expect(checkImports(root).violations, isEmpty);
      },
    );

    for (final forbidden in [
      'dart:io',
      'dart:ui',
      'dart:isolate',
      'dart:ffi',
      'dart:html',
    ]) {
      test('may not import $forbidden', () {
        write('lib/domain/a.dart', "\n\nimport '$forbidden';\n");

        expect(violationsAt(), ['lib/domain/a.dart:3']);
        expect(
          messages().single,
          startsWith('lib/domain/a.dart:3: domain may not import $forbidden ('),
        );
      });
    }

    test('may not import Flutter nor any other package', () {
      write('lib/domain/a.dart', '''
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
''');

      expect(violationsAt(), [
        'lib/domain/a.dart:1',
        'lib/domain/a.dart:2',
        'lib/domain/a.dart:3',
      ]);
    });

    for (final layer in [
      'application',
      'infrastructure',
      'presentation',
      'di',
    ]) {
      test('may not import $layer', () {
        write('lib/$layer/x.dart', '');
        write(
          'lib/domain/a.dart',
          "import 'package:boardroom/$layer/x.dart';\n",
        );

        expect(violationsAt(), ['lib/domain/a.dart:1']);
      });
    }

    test('may not climb out of the layer with a relative import', () {
      write('lib/infrastructure/x.dart', '');
      write('lib/domain/sub/a.dart', "import '../../infrastructure/x.dart';\n");

      expect(violationsAt(), ['lib/domain/sub/a.dart:1']);
    });

    test('may not import the entry point, l10n or test code', () {
      write('lib/main.dart', '');
      write('lib/l10n/app_localizations.dart', '');
      write('lib/domain/a.dart', '''
import '../main.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import '../../test/domain/support.dart';
''');

      expect(violationsAt(), [
        'lib/domain/a.dart:1',
        'lib/domain/a.dart:2',
        'lib/domain/a.dart:3',
      ]);
    });
  });

  group('directives', () {
    test('every URI of a conditional import is checked', () {
      write('lib/domain/a.dart', '''
import 'stub.dart'
    if (dart.library.io) 'dart:io'
    if (dart.library.html) 'dart:html';
''');
      write('lib/domain/stub.dart', '');

      expect(violationsAt(), ['lib/domain/a.dart:2', 'lib/domain/a.dart:3']);
    });

    test('a conditional import with allowed URIs passes', () {
      write('lib/domain/a.dart', '''
import 'stub.dart' if (dart.library.io) 'real.dart';
''');
      write('lib/domain/stub.dart', '');
      write('lib/domain/real.dart', '');

      expect(checkImports(root).violations, isEmpty);
    });

    test('conditional exports are checked too', () {
      write('lib/domain/a.dart', '''
export 'stub.dart' if (dart.library.io) 'package:dio/dio.dart';
''');
      write('lib/domain/stub.dart', '');

      expect(violationsAt(), ['lib/domain/a.dart:1']);
    });

    test('exports are checked', () {
      write('lib/domain/a.dart', "export 'package:flutter/material.dart';\n");

      expect(violationsAt(), ['lib/domain/a.dart:1']);
    });

    test('parts are checked', () {
      write('lib/infrastructure/x.dart', '');
      write('lib/domain/a.dart', "part '../infrastructure/x.dart';\n");

      expect(violationsAt(), ['lib/domain/a.dart:1']);
    });

    test('a part of with a URI that leaves the layer is checked', () {
      write('lib/domain/a.dart', "part of '../infrastructure/x.dart';\n");

      expect(violationsAt(), ['lib/domain/a.dart:1']);
    });

    test('a multi-line directive is reported on the line of the URI', () {
      write('lib/domain/a.dart', '''
import
    'package:flutter/widgets.dart'
    show Widget;
''');

      expect(violationsAt(), ['lib/domain/a.dart:2']);
    });

    test('imports with prefix, show and hide are read', () {
      write('lib/domain/a.dart', '''
import 'dart:io' as io show File;
import 'dart:io' hide File;
''');

      expect(violationsAt(), ['lib/domain/a.dart:1', 'lib/domain/a.dart:2']);
    });

    test('comments and strings that look like imports are ignored', () {
      write('lib/domain/a.dart', '''
// import 'package:flutter/widgets.dart';
/* import 'dart:io';
   export 'package:dio/dio.dart'; */
/// import 'package:flutter/material.dart';
const doc = "import 'package:flutter/widgets.dart';";
const multi = """
import 'dart:io';
""";
''');

      expect(checkImports(root).violations, isEmpty);
    });

    test('an unsupported scheme and a path outside the project fail', () {
      write('lib/domain/a.dart', '''
import 'file:///tmp/x.dart';
import '../../../outside.dart';
import '/absolute.dart';
''');

      expect(violationsAt(), [
        'lib/domain/a.dart:1',
        'lib/domain/a.dart:2',
        'lib/domain/a.dart:3',
      ]);
    });

    test('a file that does not parse fails instead of passing silently', () {
      write(
        'lib/domain/a.dart',
        'import "package:flutter/widgets.dart"\nclass {{{\n',
      );

      expect(violationsAt(), hasLength(1));
      expect(messages().single, contains('does not parse'));
    });
  });

  group('application', () {
    test('may import the domain, itself and pure packages', () {
      write('lib/domain/a.dart', '');
      write('lib/application/u.dart', '''
import 'package:boardroom/domain/a.dart';
import 'package:meta/meta.dart';
import 'dart:async';
import 'v.dart';
''');
      write('lib/application/v.dart', '');

      expect(checkImports(root).violations, isEmpty);
    });

    test(
      'may not import infrastructure, presentation, di, dart:io or a package',
      () {
        write('lib/infrastructure/i.dart', '');
        write('lib/presentation/p.dart', '');
        write('lib/di/d.dart', '');
        write('lib/application/u.dart', '''
import 'package:boardroom/infrastructure/i.dart';
import 'package:boardroom/presentation/p.dart';
import 'package:boardroom/di/d.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
''');

        expect(violationsAt(), [
          for (var line = 1; line <= 5; line++) 'lib/application/u.dart:$line',
        ]);
      },
    );
  });

  group('infrastructure', () {
    test(
      'may import domain, application, itself, any dart: and any package',
      () {
        write('lib/domain/a.dart', '');
        write('lib/application/u.dart', '');
        write('lib/infrastructure/i.dart', '''
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:boardroom/domain/a.dart';
import 'package:boardroom/application/u.dart';
import 'j.dart';
''');
        write('lib/infrastructure/j.dart', '');

        expect(checkImports(root).violations, isEmpty);
      },
    );

    test('may not import presentation nor di', () {
      write('lib/presentation/p.dart', '');
      write('lib/di/d.dart', '');
      write('lib/infrastructure/i.dart', '''
import 'package:boardroom/presentation/p.dart';
import '../di/d.dart';
''');

      expect(violationsAt(), [
        'lib/infrastructure/i.dart:1',
        'lib/infrastructure/i.dart:2',
      ]);
    });
  });

  group('presentation', () {
    test(
      'may import domain, application, di, itself, l10n, dart: and packages',
      () {
        write('lib/domain/a.dart', '');
        write('lib/application/u.dart', '');
        write('lib/di/d.dart', '');
        write('lib/l10n/app_localizations.dart', '');
        write('lib/presentation/p.dart', '''
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:boardroom/domain/a.dart';
import 'package:boardroom/application/u.dart';
import 'package:boardroom/di/d.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'q.dart';
''');
        write('lib/presentation/q.dart', '');

        expect(checkImports(root).violations, isEmpty);
      },
    );

    test('may not import infrastructure directly', () {
      write('lib/infrastructure/i.dart', '');
      write('lib/presentation/p.dart', '''
import 'package:boardroom/infrastructure/i.dart';
import '../infrastructure/i.dart';
export '../infrastructure/i.dart';
''');

      expect(violationsAt(), [
        'lib/presentation/p.dart:1',
        'lib/presentation/p.dart:2',
        'lib/presentation/p.dart:3',
      ]);
      expect(messages().first, contains('through the providers of di'));
    });
  });

  group('adapter packages', () {
    const adapters = [
      'package:connectivity_plus/connectivity_plus.dart',
      'package:dio/dio.dart',
      'package:drift/drift.dart',
      'package:drift_flutter/drift_flutter.dart',
      'package:flutter_secure_storage/flutter_secure_storage.dart',
      'package:local_auth/local_auth.dart',
      'package:local_auth_android/local_auth_android.dart',
      'package:local_auth_darwin/local_auth_darwin.dart',
      'package:path_provider/path_provider.dart',
      'package:path_provider_android/path_provider_android.dart',
      'package:screen_protection/screen_protection.dart',
      'package:sqlite3/sqlite3.dart',
    ];

    for (final layer in ['presentation', 'di']) {
      test('$layer may not import them directly', () {
        write(
          'lib/$layer/a.dart',
          [for (final uri in adapters) "import '$uri';"].join('\n'),
        );

        expect(violationsAt(), [
          for (var line = 1; line <= adapters.length; line++)
            'lib/$layer/a.dart:$line',
        ]);
        expect(messages().first, contains('belongs to the adapters'));
      });
    }

    test('application may not import them either', () {
      write('lib/application/u.dart', "import 'package:dio/dio.dart';\n");

      expect(violationsAt(), ['lib/application/u.dart:1']);
    });

    test('infrastructure may import them', () {
      write(
        'lib/infrastructure/i.dart',
        [for (final uri in adapters) "import '$uri';"].join('\n'),
      );

      expect(checkImports(root).violations, isEmpty);
    });

    test('a package that only shares the prefix is not an adapter', () {
      write('lib/presentation/p.dart', '''
import 'package:dioramas/dioramas.dart';
import 'package:drifting/drifting.dart';
''');

      expect(checkImports(root).violations, isEmpty);
    });
  });

  group('di', () {
    test(
      'may import domain, application, infrastructure, itself and packages',
      () {
        write('lib/domain/a.dart', '');
        write('lib/application/u.dart', '');
        write('lib/infrastructure/i.dart', '');
        write('lib/di/d.dart', '''
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boardroom/domain/a.dart';
import 'package:boardroom/application/u.dart';
import 'package:boardroom/infrastructure/i.dart';
import 'e.dart';
''');
        write('lib/di/e.dart', '');

        expect(checkImports(root).violations, isEmpty);
      },
    );

    test('may not import presentation nor l10n', () {
      write('lib/presentation/p.dart', '');
      write('lib/l10n/app_localizations.dart', '');
      write('lib/di/d.dart', '''
import 'package:boardroom/presentation/p.dart';
import 'package:boardroom/l10n/app_localizations.dart';
''');

      expect(violationsAt(), ['lib/di/d.dart:1', 'lib/di/d.dart:2']);
    });
  });

  group('entry point and localization', () {
    test('main.dart and lib/l10n may import anything in lib', () {
      write('lib/infrastructure/i.dart', '');
      write('lib/presentation/p.dart', '');
      write('lib/domain/a.dart', '');
      write('lib/main.dart', '''
import 'package:flutter/widgets.dart';
import 'package:boardroom/infrastructure/i.dart';
import 'package:boardroom/presentation/p.dart';
import 'package:boardroom/domain/a.dart';
''');
      write('lib/l10n/app_localizations.dart', '''
import 'dart:io';
import 'package:boardroom/domain/a.dart';
''');

      expect(checkImports(root).violations, isEmpty);
    });
  });

  group('lib/l10n', () {
    test('a hand-written file is outside the layers', () {
      write('lib/infrastructure/x.dart', '');
      write('lib/l10n/evil.dart', '''
import 'package:boardroom/infrastructure/x.dart';
''');
      write('lib/presentation/p.dart', "import '../l10n/evil.dart';\n");

      expect(violationsAt(), [
        'lib/l10n/evil.dart:1',
        'lib/presentation/p.dart:1',
      ]);
      expect(messages().first, contains('file outside the layers'));
    });

    test('every file written by gen-l10n is exempt', () {
      for (final name in [
        'app_localizations.dart',
        'app_localizations_en.dart',
        'app_localizations_fr.dart',
      ]) {
        write('lib/l10n/$name', "import 'dart:io';\n");
      }

      expect(checkImports(root).violations, isEmpty);
    });

    test('a generated name in a sub folder is not exempt', () {
      write('lib/l10n/sub/app_localizations.dart', '');

      expect(violationsAt(), ['lib/l10n/sub/app_localizations.dart:1']);
    });
  });

  group('placement', () {
    test('a file directly under lib/ other than main.dart is a violation', () {
      write('lib/stray.dart', '');

      expect(violationsAt(), ['lib/stray.dart:1']);
      expect(messages().single, contains('file outside the layers'));
    });

    test('a file in a folder that is not a layer is a violation', () {
      write('lib/utils/helper.dart', '');
      write('lib/domain/deep/ok.dart', '');

      expect(violationsAt(), ['lib/utils/helper.dart:1']);
    });

    test('a layer may not import a file that belongs to no layer', () {
      write('lib/utils/helper.dart', '');
      write('lib/infrastructure/i.dart', "import '../utils/helper.dart';\n");

      expect(violationsAt(), [
        'lib/infrastructure/i.dart:1',
        'lib/utils/helper.dart:1',
      ]);
    });
  });

  group('generated files', () {
    test('are checked like their source', () {
      write('lib/domain/a.dart', "part 'a.freezed.dart';\n");
      write('lib/domain/a.freezed.dart', '''
part of 'a.dart';
''');
      write('lib/domain/b.g.dart', "import 'dart:io';\n");

      expect(violationsAt(), ['lib/domain/b.g.dart:1']);
    });
  });

  group('tests', () {
    test('test/domain follows the domain rules plus package:test and its own support', () {
      write('lib/domain/a.dart', '');
      write('test/domain/support/fake.dart', '');
      write('test/domain/a_test.dart', '''
import 'package:test/test.dart';
import 'package:boardroom/domain/a.dart';
import '../../lib/domain/a.dart';
import 'support/fake.dart';
import 'dart:async';
''');

      expect(checkImports(root).violations, isEmpty);
    });

    test('test/domain may not import flutter_test, Flutter nor dart:io', () {
      write('test/domain/a_test.dart', '''
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'dart:io';
''');

      expect(violationsAt(), [
        'test/domain/a_test.dart:1',
        'test/domain/a_test.dart:2',
        'test/domain/a_test.dart:3',
      ]);
      expect(
        messages().first,
        contains('test/domain may not import package:flutter_test'),
      );
      expect(messages().first, contains('plain `dart test`'));
    });

    test(
      'test/domain may not import the application nor other test folders',
      () {
        write('lib/application/u.dart', '');
        write('test/application/support.dart', '');
        write('test/presentation/helper.dart', '');
        write('test/domain/a_test.dart', '''
import 'package:boardroom/application/u.dart';
import '../application/support.dart';
import '../presentation/helper.dart';
''');

        expect(violationsAt(), [
          'test/domain/a_test.dart:1',
          'test/domain/a_test.dart:2',
          'test/domain/a_test.dart:3',
        ]);
      },
    );

    test('test/application may use the domain, the application and domain test support', () {
      write('lib/domain/a.dart', '');
      write('lib/application/u.dart', '');
      write('test/domain/support.dart', '');
      write('test/application/support.dart', '');
      write('test/application/u_test.dart', '''
import 'package:test/test.dart';
import 'package:boardroom/domain/a.dart';
import 'package:boardroom/application/u.dart';
import '../domain/support.dart';
import 'support.dart';
''');

      expect(checkImports(root).violations, isEmpty);
    });

    test('test/application may not import infrastructure nor flutter_test', () {
      write('lib/infrastructure/i.dart', '');
      write('test/application/u_test.dart', '''
import 'package:boardroom/infrastructure/i.dart';
import 'package:flutter_test/flutter_test.dart';
''');

      expect(violationsAt(), [
        'test/application/u_test.dart:1',
        'test/application/u_test.dart:2',
      ]);
    });

    test('the other test folders are free', () {
      write('lib/infrastructure/i.dart', '');
      write('test/presentation/p_test.dart', '''
import 'package:flutter_test/flutter_test.dart';
import 'package:boardroom/infrastructure/i.dart';
import 'dart:io';
''');
      write(
        'test/tool/t_test.dart',
        "import 'package:analyzer/dart/ast/ast.dart';\n",
      );
      write(
        'test/widget_test.dart',
        "import 'package:flutter_test/flutter_test.dart';\n",
      );

      expect(checkImports(root).violations, isEmpty);
    });
  });

  group('report', () {
    test('prints one line per violation and exits 1', () {
      write('lib/domain/a.dart', "import 'dart:io';\n");
      final out = StringBuffer();

      final code = report(checkImports(root), out);

      expect(code, 1);
      expect(
        out.toString(),
        'lib/domain/a.dart:1: domain may not import dart:io '
        '(dart:io is tied to a platform; allowed: dart:async, '
        'dart:collection, dart:convert, dart:core, dart:math, '
        'dart:typed_data)\n',
      );
    });

    test('prints a one-line summary and exits 0 when everything holds', () {
      write('lib/domain/a.dart', '');
      write('lib/main.dart', '');
      final out = StringBuffer();

      final code = report(checkImports(root), out);

      expect(code, 0);
      expect(out.toString().trimRight().split('\n'), hasLength(1));
      expect(out.toString(), startsWith('Import rules OK: 1 files checked'));
    });
  });

  group('the real repository', () {
    // Tests run from the package root, with `dart test` and `flutter test`.
    final repo = Directory.current;

    test('respects the rules when checked in process', () {
      expect(checkImports(repo).violations, isEmpty);
    });

    test('exits 0 when the real script runs', () {
      final result = Process.runSync('dart', [
        'run',
        'tool/check_imports.dart',
      ], workingDirectory: repo.path);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, startsWith('Import rules OK'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
