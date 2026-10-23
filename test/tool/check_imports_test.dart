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

  /// The `package:boardroom/...` URI of the project-relative [libPath].
  String uriOf(String libPath) =>
      'package:boardroom/${libPath.substring('lib/'.length)}';

  /// The violations as `path:line` strings, to assert where each is reported.
  List<String> violationsAt() => [
    for (final v in checkImports(root).violations) '${v.path}:${v.line}',
  ];

  List<String> messages() => [
    for (final v in checkImports(root).violations) v.toString(),
  ];

  group('domain', () {
    test('may import the domain of the core and of the features it depends '
        'on, itself, pure dart: libraries and allowlisted packages', () {
      write('lib/core/domain/a.dart', '');
      write('lib/features/meetings/domain/m.dart', '');
      write('lib/features/auth/domain/a.dart', '');
      write('lib/features/votes/domain/sub/b.dart', '''
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
import 'package:boardroom/core/domain/a.dart';
import 'package:boardroom/features/meetings/domain/m.dart';
import '../a.dart';
import 'b.dart';
export 'package:boardroom/core/domain/a.dart';
part 'b.g.dart';
''');
      write('lib/features/votes/domain/sub/b.g.dart', "part of 'b.dart';\n");

      expect(checkImports(root).violations, isEmpty);
    });

    for (final forbidden in [
      'dart:io',
      'dart:ui',
      'dart:isolate',
      'dart:ffi',
      'dart:html',
    ]) {
      test('may not import $forbidden', () {
        write('lib/core/domain/a.dart', "\n\nimport '$forbidden';\n");

        expect(violationsAt(), ['lib/core/domain/a.dart:3']);
        expect(
          messages().single,
          startsWith(
            'lib/core/domain/a.dart:3: domain may not import $forbidden (',
          ),
        );
      });
    }

    test('may not import Flutter nor any other package', () {
      write('lib/features/auth/domain/a.dart', '''
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
''');

      expect(violationsAt(), [
        'lib/features/auth/domain/a.dart:1',
        'lib/features/auth/domain/a.dart:2',
        'lib/features/auth/domain/a.dart:3',
      ]);
    });

    for (final MapEntry(key: layer, value: path) in {
      'application': 'lib/core/application/x.dart',
      'infrastructure': 'lib/features/auth/infrastructure/x.dart',
      'presentation': 'lib/features/auth/presentation/x.dart',
      'app': 'lib/app/x.dart',
    }.entries) {
      test('may not import $layer', () {
        write(path, '');
        write('lib/core/domain/a.dart', "import '${uriOf(path)}';\n");

        expect(violationsAt(), ['lib/core/domain/a.dart:1']);
      });
    }

    test('may not climb out of the layer with a relative import', () {
      write('lib/core/infrastructure/x.dart', '');
      write(
        'lib/core/domain/sub/a.dart',
        "import '../../infrastructure/x.dart';\n",
      );

      expect(violationsAt(), ['lib/core/domain/sub/a.dart:1']);
    });

    test('may not import the entry point, l10n or test code', () {
      write('lib/main.dart', '');
      write('lib/l10n/app_localizations.dart', '');
      write('lib/core/domain/a.dart', '''
import '../../main.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import '../../../test/support/builders/builders.dart';
''');

      expect(violationsAt(), [
        'lib/core/domain/a.dart:1',
        'lib/core/domain/a.dart:2',
        'lib/core/domain/a.dart:3',
      ]);
    });
  });

  group('directives', () {
    test('every URI of a conditional import is checked, the allowed ones '
        'pass', () {
      write('lib/core/domain/a.dart', '''
import 'stub.dart'
    if (dart.library.io) 'dart:io'
    if (dart.library.html) 'dart:html';
''');
      write('lib/core/domain/c.dart', '''
import 'stub.dart' if (dart.library.io) 'real.dart';
''');
      write('lib/core/domain/stub.dart', '');
      write('lib/core/domain/real.dart', '');

      expect(violationsAt(), [
        'lib/core/domain/a.dart:2',
        'lib/core/domain/a.dart:3',
      ]);
    });

    test('exports are checked, the conditional ones too', () {
      write('lib/core/domain/a.dart', '''
export 'stub.dart' if (dart.library.io) 'package:dio/dio.dart';
''');
      write(
        'lib/core/domain/b.dart',
        "export 'package:flutter/material.dart';\n",
      );
      write('lib/core/domain/stub.dart', '');

      expect(violationsAt(), [
        'lib/core/domain/a.dart:1',
        'lib/core/domain/b.dart:1',
      ]);
    });

    test(
      'parts are checked, a part of with a URI that leaves the layer too',
      () {
        write('lib/core/infrastructure/x.dart', '');
        write('lib/core/domain/a.dart', "part '../infrastructure/x.dart';\n");
        write(
          'lib/core/domain/b.dart',
          "part of '../infrastructure/x.dart';\n",
        );

        expect(violationsAt(), [
          'lib/core/domain/a.dart:1',
          'lib/core/domain/b.dart:1',
        ]);
      },
    );

    test('a multi-line directive is reported on the line of the URI', () {
      write('lib/core/domain/a.dart', '''
import
    'package:flutter/widgets.dart'
    show Widget;
''');

      expect(violationsAt(), ['lib/core/domain/a.dart:2']);
    });

    test('imports with prefix, show and hide are read', () {
      write('lib/core/domain/a.dart', '''
import 'dart:io' as io show File;
import 'dart:io' hide File;
''');

      expect(violationsAt(), [
        'lib/core/domain/a.dart:1',
        'lib/core/domain/a.dart:2',
      ]);
    });

    test('comments and strings that look like imports are ignored', () {
      write('lib/core/domain/a.dart', '''
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
      write('lib/core/domain/a.dart', '''
import 'file:///tmp/x.dart';
import '../../../../outside.dart';
import '/absolute.dart';
''');

      expect(violationsAt(), [
        'lib/core/domain/a.dart:1',
        'lib/core/domain/a.dart:2',
        'lib/core/domain/a.dart:3',
      ]);
    });

    test('a file that does not parse fails instead of passing silently', () {
      write(
        'lib/core/domain/a.dart',
        'import "package:flutter/widgets.dart"\nclass {{{\n',
      );

      expect(violationsAt(), hasLength(1));
      expect(messages().single, contains('does not parse'));
    });
  });

  group('application', () {
    test('may import the domain of the core and of the features it depends '
        'on, itself and pure packages', () {
      write('lib/core/domain/a.dart', '');
      write('lib/features/meetings/application/m.dart', '');
      write('lib/features/votes/application/u.dart', '''
import 'package:boardroom/core/domain/a.dart';
import 'package:boardroom/features/meetings/application/m.dart';
import 'package:meta/meta.dart';
import 'dart:async';
import 'v.dart';
''');
      write('lib/features/votes/application/v.dart', '');

      expect(checkImports(root).violations, isEmpty);
    });

    test(
      'may not import infrastructure, presentation, app, dart:io or a package',
      () {
        write('lib/core/infrastructure/i.dart', '');
        write('lib/features/auth/presentation/p.dart', '');
        write('lib/app/d.dart', '');
        write('lib/core/application/u.dart', '''
import 'package:boardroom/core/infrastructure/i.dart';
import 'package:boardroom/features/auth/presentation/p.dart';
import 'package:boardroom/app/d.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
''');

        expect(violationsAt(), [
          for (var line = 1; line <= 5; line++)
            'lib/core/application/u.dart:$line',
        ]);
      },
    );
  });

  group('infrastructure', () {
    test(
      'may import domain, application, itself, any dart: and any package',
      () {
        write('lib/core/domain/a.dart', '');
        write('lib/features/meetings/application/u.dart', '');
        write('lib/features/votes/infrastructure/i.dart', '''
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:boardroom/core/domain/a.dart';
import 'package:boardroom/features/meetings/application/u.dart';
import 'j.dart';
''');
        write('lib/features/votes/infrastructure/j.dart', '');

        expect(checkImports(root).violations, isEmpty);
      },
    );

    test('may not import presentation nor app', () {
      write('lib/core/presentation/p.dart', '');
      write('lib/app/d.dart', '');
      write('lib/features/auth/infrastructure/i.dart', '''
import 'package:boardroom/core/presentation/p.dart';
import '../../../app/d.dart';
''');

      expect(violationsAt(), [
        'lib/features/auth/infrastructure/i.dart:1',
        'lib/features/auth/infrastructure/i.dart:2',
      ]);
    });

    test('may not import lib/app, from the core or from a feature', () {
      write('lib/app/persistence/db.dart', '');
      write('lib/core/infrastructure/persistence/open.dart', '''
import 'package:boardroom/app/persistence/db.dart';
''');
      write('lib/features/auth/infrastructure/i.dart', '''
import 'package:boardroom/app/persistence/db.dart';
''');

      expect(violationsAt(), [
        'lib/core/infrastructure/persistence/open.dart:1',
        'lib/features/auth/infrastructure/i.dart:1',
      ]);
      expect(messages().first, contains('the core imports not app'));
      expect(messages().last, contains('a feature imports not app'));
    });
  });

  group('presentation', () {
    test(
      'may import domain, application, itself, l10n, dart: and packages',
      () {
        write('lib/core/domain/a.dart', '');
        write('lib/features/meetings/application/u.dart', '');
        write('lib/l10n/app_localizations.dart', '');
        write('lib/features/votes/presentation/p.dart', '''
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:boardroom/core/domain/a.dart';
import 'package:boardroom/features/meetings/application/u.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'q.dart';
''');
        write('lib/features/votes/presentation/q.dart', '');

        expect(checkImports(root).violations, isEmpty);
      },
    );

    test('may not import infrastructure directly, nor app', () {
      write('lib/core/infrastructure/i.dart', '');
      write('lib/app/d.dart', '');
      write('lib/features/auth/presentation/p.dart', '''
import 'package:boardroom/core/infrastructure/i.dart';
import '../../../core/infrastructure/i.dart';
export '../../../core/infrastructure/i.dart';
import 'package:boardroom/app/d.dart';
''');

      expect(violationsAt(), [
        'lib/features/auth/presentation/p.dart:1',
        'lib/features/auth/presentation/p.dart:2',
        'lib/features/auth/presentation/p.dart:3',
        'lib/features/auth/presentation/p.dart:4',
      ]);
      expect(messages().first, contains('never imports an adapter'));
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

    for (final path in [
      'lib/core/presentation/a.dart',
      'lib/features/auth/presentation/a.dart',
    ]) {
      test('$path may not import them directly', () {
        write(path, [for (final uri in adapters) "import '$uri';"].join('\n'));

        expect(violationsAt(), [
          for (var line = 1; line <= adapters.length; line++) '$path:$line',
        ]);
        expect(messages().first, contains('belongs to the adapters'));
      });
    }

    test('application may not import them either', () {
      write(
        'lib/features/auth/application/u.dart',
        "import 'package:dio/dio.dart';\n",
      );

      expect(violationsAt(), ['lib/features/auth/application/u.dart:1']);
    });

    test('infrastructure may import them', () {
      write(
        'lib/core/infrastructure/i.dart',
        [for (final uri in adapters) "import '$uri';"].join('\n'),
      );

      expect(checkImports(root).violations, isEmpty);
    });

    test('a package that only shares the prefix is not an adapter', () {
      write('lib/features/auth/presentation/p.dart', '''
import 'package:dioramas/dioramas.dart';
import 'package:drifting/drifting.dart';
''');

      expect(checkImports(root).violations, isEmpty);
    });
  });

  group('the exemption of the secure view', () {
    const secureContent =
        'lib/features/documents/presentation/secure_content.dart';
    const widgetEntry = 'package:screen_protection/screen_protection_view.dart';
    const pdfView =
        'lib/features/documents/presentation/components/pdf_view.dart';
    const pdfEngine = 'package:pdfrx/pdfrx.dart';

    test('is listed for one file and one URI only', () {
      expect(presentationExemptions, {
        secureContent: {widgetEntry},
        pdfView: {pdfEngine},
      });
    });

    test('lets the secure content import the widget entry point', () {
      write(secureContent, "import '$widgetEntry';\n");

      expect(checkImports(root).violations, isEmpty);
    });

    test('does not let it import the calls and the events of the plugin', () {
      write(secureContent, """
import '$widgetEntry';
import 'package:screen_protection/screen_protection.dart';
""");

      expect(violationsAt(), ['$secureContent:2']);
      expect(messages().single, contains('belongs to the adapters'));
    });

    test('does not let another file of the presentation import the widget', () {
      write(
        'lib/features/documents/presentation/other.dart',
        "import '$widgetEntry';\n",
      );
      write(
        'lib/features/votes/presentation/secure_content.dart',
        "import '$widgetEntry';\n",
      );

      expect(violationsAt(), [
        'lib/features/documents/presentation/other.dart:1',
        'lib/features/votes/presentation/secure_content.dart:1',
      ]);
    });
  });

  group('the exemption of the PDF viewer', () {
    const pdfView =
        'lib/features/documents/presentation/components/pdf_view.dart';
    const pdfEngine = 'package:pdfrx/pdfrx.dart';

    test('pdfrx is an adapter package', () {
      expect(adapterPackages, contains('pdfrx'));
    });

    test('lets the PDF view import the engine', () {
      write(pdfView, "import '$pdfEngine';\n");

      expect(checkImports(root).violations, isEmpty);
    });

    test('does not let it import another file of the engine', () {
      write(pdfView, """
import '$pdfEngine';
import 'package:pdfrx_engine/pdfrx_engine.dart';
""");

      expect(violationsAt(), ['$pdfView:2']);
      expect(messages().single, contains('belongs to the adapters'));
    });

    test('does not let another file of the presentation import the engine', () {
      write(
        'lib/features/documents/presentation/components/other_view.dart',
        "import '$pdfEngine';\n",
      );
      write(
        'lib/features/meetings/presentation/components/pdf_view.dart',
        "import '$pdfEngine';\n",
      );

      expect(violationsAt(), [
        'lib/features/documents/presentation/components/other_view.dart:1',
        'lib/features/meetings/presentation/components/pdf_view.dart:1',
      ]);
    });

    test('does not check a test of the presentation, which fakes the '
        'document', () {
      write(
        'test/features/documents/presentation/components/pdf_view_test.dart',
        "import '$pdfEngine';\n",
      );

      expect(checkImports(root).violations, isEmpty);
    });
  });

  group('app', () {
    test('may import every layer of the core and of the features, itself, '
        'l10n, any dart: and any package', () {
      write('lib/core/domain/a.dart', '');
      write('lib/features/auth/application/u.dart', '');
      write('lib/core/infrastructure/i.dart', '');
      write('lib/features/auth/presentation/p.dart', '');
      write('lib/l10n/app_localizations.dart', '');
      write('lib/app/d.dart', '''
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boardroom/core/domain/a.dart';
import 'package:boardroom/features/auth/application/u.dart';
import 'package:boardroom/core/infrastructure/i.dart';
import 'package:boardroom/features/auth/presentation/p.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'dev/e.dart';
''');
      write('lib/app/dev/e.dart', '');

      expect(checkImports(root).violations, isEmpty);
    });

    test('may not import the entry point nor test code', () {
      write('lib/main.dart', '');
      write('test/support/builders/builders.dart', '');
      write('lib/app/d.dart', '''
import '../main.dart';
import '../../test/support/builders/builders.dart';
''');

      expect(violationsAt(), ['lib/app/d.dart:1', 'lib/app/d.dart:2']);
    });
  });

  group('composition (lib/app/composition)', () {
    test('may import the domain and the application of any feature, itself, '
        'pure dart: libraries and allowlisted packages', () {
      write('lib/core/domain/a.dart', '');
      write('lib/features/meetings/application/m.dart', '');
      write('lib/features/votes/domain/v.dart', '');
      write('lib/app/composition/other.dart', '');
      write('lib/app/composition/glue.dart', '''
import 'dart:async';
import 'package:meta/meta.dart';
import 'package:boardroom/core/domain/a.dart';
import 'package:boardroom/features/meetings/application/m.dart';
import 'package:boardroom/features/votes/domain/v.dart';
import 'package:boardroom/app/composition/other.dart';
import 'other.dart';
''');

      expect(checkImports(root).violations, isEmpty);
    });

    test('may not import an adapter, the UI, the rest of app, dart:io nor an '
        'adapter package', () {
      write('lib/features/meetings/infrastructure/i.dart', '');
      write('lib/features/meetings/presentation/p.dart', '');
      write('lib/app/persistence/db.dart', '');
      write('lib/app/composition/glue.dart', '''
import 'package:boardroom/features/meetings/infrastructure/i.dart';
import 'package:boardroom/features/meetings/presentation/p.dart';
import 'package:boardroom/app/persistence/db.dart';
import 'dart:io';
import 'package:dio/dio.dart';
''');

      expect(violationsAt(), [
        'lib/app/composition/glue.dart:1',
        'lib/app/composition/glue.dart:2',
        'lib/app/composition/glue.dart:3',
        'lib/app/composition/glue.dart:4',
        'lib/app/composition/glue.dart:5',
      ]);
      expect(messages().first, contains('composition may not import'));
      expect(messages().first, contains('pure Dart'));
    });

    test('is imported by the rest of app, and by no other layer', () {
      write('lib/app/composition/glue.dart', '');
      write('lib/app/app.dart', "import 'composition/glue.dart';\n");
      for (final path in [
        'lib/core/domain/a.dart',
        'lib/core/application/a.dart',
        'lib/features/auth/infrastructure/a.dart',
        'lib/features/auth/presentation/a.dart',
      ]) {
        write(path, "import 'package:boardroom/app/composition/glue.dart';\n");
      }

      expect(violationsAt(), [
        'lib/core/application/a.dart:1',
        'lib/core/domain/a.dart:1',
        'lib/features/auth/infrastructure/a.dart:1',
        'lib/features/auth/presentation/a.dart:1',
      ]);
    });

    test('is a layer of the pure test support: the fakes assemble the same '
        'glue as the app, the builders and the contracts do not', () {
      write('lib/app/composition/glue.dart', '');
      write('test/support/fakes/f.dart', '''
import 'package:boardroom/app/composition/glue.dart';
''');
      write('test/support/builders/b.dart', '''
import 'package:boardroom/app/composition/glue.dart';
''');
      write('test/support/contracts/c.dart', '''
import 'package:boardroom/app/composition/glue.dart';
''');

      expect(violationsAt(), [
        'test/support/builders/b.dart:1',
        'test/support/contracts/c.dart:1',
      ]);
    });

    test('test/app/composition runs under dart test: the glue, the support '
        'and its own folder, no Flutter', () {
      write('lib/app/composition/glue.dart', '');
      write('test/support/fakes/f.dart', '');
      write('test/app/composition/helper.dart', '');
      write('test/app/composition/glue_test.dart', '''
import 'package:test/test.dart';
import 'package:boardroom/app/composition/glue.dart';
import '../../support/fakes/f.dart';
import 'helper.dart';
''');
      write('test/app/composition/bad_test.dart', '''
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
''');

      expect(violationsAt(), [
        'test/app/composition/bad_test.dart:1',
        'test/app/composition/bad_test.dart:2',
      ]);
    });
  });

  group('features', () {
    test('a feature may import the core, itself, and the domain and the '
        'application of the features its graph names', () {
      write('lib/core/domain/c.dart', '');
      write('lib/core/application/c.dart', '');
      write('lib/features/auth/domain/u.dart', '');
      write('lib/features/auth/application/s.dart', '');
      write('lib/features/meetings/domain/m.dart', '');
      write('lib/features/meetings/application/m.dart', '');
      write('lib/features/documents/application/d.dart', '''
import 'package:boardroom/core/domain/c.dart';
import 'package:boardroom/features/auth/domain/u.dart';
import 'package:boardroom/features/auth/application/s.dart';
import '../../meetings/domain/m.dart';
import 'package:boardroom/features/meetings/application/m.dart';
''');
      write('lib/features/votes/application/v.dart', '''
import 'package:boardroom/core/application/c.dart';
import 'package:boardroom/features/auth/application/s.dart';
import 'package:boardroom/features/meetings/domain/m.dart';
''');
      write('lib/features/meetings/application/uses.dart', '''
import 'package:boardroom/features/auth/application/s.dart';
''');

      expect(checkImports(root).violations, isEmpty);
    });

    test('a feature may not import a feature its graph does not name, from '
        'any layer', () {
      write('lib/features/votes/domain/v.dart', '');
      write('lib/features/documents/application/d.dart', '');
      write('lib/features/meetings/domain/m.dart', '''
import 'package:boardroom/features/votes/domain/v.dart';
''');
      write('lib/features/auth/application/a.dart', '''
import 'package:boardroom/core/domain/x.dart';
import 'package:boardroom/features/documents/application/d.dart';
''');
      write('lib/features/votes/application/v.dart', '''
import '../../documents/application/d.dart';
''');
      write('lib/core/domain/x.dart', '');

      expect(violationsAt(), [
        'lib/features/auth/application/a.dart:2',
        'lib/features/meetings/domain/m.dart:1',
        'lib/features/votes/application/v.dart:1',
      ]);
      expect(
        messages().first,
        contains(
          'the feature auth does not depend on the feature documents '
          '(featureGraph: auth depends on no other feature)',
        ),
      );
      expect(messages()[1], contains('meetings depends on auth'));
    });

    test('a feature may never import the infrastructure of another, nor its '
        'presentation except from a presentation, even for one it depends '
        'on', () {
      write('lib/features/auth/infrastructure/i.dart', '');
      write('lib/features/auth/presentation/p.dart', '');
      write('lib/features/meetings/infrastructure/i.dart', '');
      write('lib/features/meetings/application/m.dart', '''
import 'package:boardroom/features/auth/infrastructure/i.dart';
import 'package:boardroom/features/auth/presentation/p.dart';
''');
      write('lib/features/documents/infrastructure/d.dart', '''
import 'package:boardroom/features/meetings/infrastructure/i.dart';
import '../../auth/infrastructure/i.dart';
import 'package:boardroom/features/meetings/application/m.dart';
''');
      write('lib/features/meetings/presentation/q.dart', '');

      expect(violationsAt(), [
        'lib/features/documents/infrastructure/d.dart:1',
        'lib/features/documents/infrastructure/d.dart:2',
        'lib/features/meetings/application/m.dart:1',
        'lib/features/meetings/application/m.dart:2',
      ]);
      expect(
        messages().first,
        contains('never the infrastructure of another feature'),
      );
      expect(
        messages()[3],
        contains('never the presentation of another feature'),
      );
    });

    test('the presentation of a feature may import the presentation of a '
        'feature it depends on, never an adapter, and not the presentation of '
        'a feature it does not depend on', () {
      write('lib/features/auth/presentation/p.dart', '');
      write('lib/features/auth/infrastructure/i.dart', '');
      write('lib/features/documents/presentation/q.dart', '');
      write('lib/features/meetings/presentation/m.dart', '''
import 'package:boardroom/features/auth/presentation/p.dart';
import '../../auth/presentation/p.dart';
import 'package:boardroom/features/auth/infrastructure/i.dart';
import 'package:boardroom/features/documents/presentation/q.dart';
''');

      expect(violationsAt(), [
        'lib/features/meetings/presentation/m.dart:3',
        'lib/features/meetings/presentation/m.dart:4',
      ]);
      expect(messages().first, contains('never the infrastructure'));
      expect(
        messages()[1],
        contains('the feature meetings does not depend on the feature'),
      );
    });

    test('the presentation never imports app, from a feature or the core', () {
      write('lib/app/providers/p.dart', '');
      write('lib/features/auth/presentation/a.dart', '''
import 'package:boardroom/app/providers/p.dart';
''');
      write('lib/core/presentation/b.dart', '''
import 'package:boardroom/app/providers/p.dart';
''');

      expect(violationsAt(), [
        'lib/core/presentation/b.dart:1',
        'lib/features/auth/presentation/a.dart:1',
      ]);
    });

    test('the core imports no feature and not app', () {
      write('lib/features/auth/domain/u.dart', '');
      write('lib/features/auth/application/s.dart', '');
      write('lib/features/auth/infrastructure/i.dart', '');
      write('lib/app/persistence/db.dart', '');
      write('lib/core/domain/d.dart', '''
import 'package:boardroom/features/auth/domain/u.dart';
''');
      write('lib/core/application/a.dart', '''
import 'package:boardroom/features/auth/application/s.dart';
import '../../app/persistence/db.dart';
''');
      write('lib/core/infrastructure/i.dart', '''
import 'package:boardroom/features/auth/infrastructure/i.dart';
import 'package:boardroom/features/auth/domain/u.dart';
import 'package:boardroom/app/persistence/db.dart';
''');

      expect(violationsAt(), [
        'lib/core/application/a.dart:1',
        'lib/core/application/a.dart:2',
        'lib/core/domain/d.dart:1',
        'lib/core/infrastructure/i.dart:1',
        'lib/core/infrastructure/i.dart:2',
        'lib/core/infrastructure/i.dart:3',
      ]);
      expect(messages().first, contains('the core imports no feature'));
      expect(messages()[1], contains('the core imports not app'));
    });

    test('a feature may not import app', () {
      write('lib/app/composition/glue.dart', '');
      write('lib/features/votes/application/v.dart', '''
import 'package:boardroom/app/composition/glue.dart';
''');

      expect(violationsAt(), ['lib/features/votes/application/v.dart:1']);
      expect(messages().single, contains('a feature imports not app'));
    });

    test('app, its composition and the entry point know every feature', () {
      write('lib/features/auth/infrastructure/i.dart', '');
      write('lib/features/votes/infrastructure/v.dart', '');
      write('lib/features/votes/domain/v.dart', '');
      write('lib/features/documents/application/d.dart', '');
      write('lib/app/dev/backend.dart', '''
import 'package:boardroom/features/auth/infrastructure/i.dart';
import 'package:boardroom/features/votes/infrastructure/v.dart';
import 'package:boardroom/features/documents/application/d.dart';
''');
      write('lib/app/composition/glue.dart', '''
import 'package:boardroom/features/votes/domain/v.dart';
import 'package:boardroom/features/documents/application/d.dart';
''');
      write('lib/main.dart', '''
import 'package:boardroom/features/votes/infrastructure/v.dart';
''');

      expect(checkImports(root).violations, isEmpty);
    });

    test('a feature that the graph does not list is a violation', () {
      write('lib/features/billing/domain/b.dart', '');

      expect(violationsAt(), ['lib/features/billing:1']);
      expect(
        messages().single,
        contains('the feature billing is not in featureGraph'),
      );
    });

    test('follows the graph it is given', () {
      write('lib/features/auth/domain/u.dart', '');
      write('lib/features/votes/domain/v.dart', '''
import 'package:boardroom/features/auth/domain/u.dart';
''');
      write('lib/features/auth/application/a.dart', '''
import 'package:boardroom/features/votes/domain/v.dart';
''');
      const reversed = {
        'auth': {'votes': 'for the test'},
        'votes': <String, String>{},
      };

      final result = checkImports(root, graph: reversed);

      expect(
        [for (final v in result.violations) '${v.path}:${v.line}'],
        ['lib/features/votes/domain/v.dart:1'],
      );
    });

    test('refuses a graph with a cycle, and names it', () {
      write('lib/features/auth/domain/u.dart', '');
      write('lib/features/votes/domain/v.dart', '');
      const cyclic = {
        'auth': {'votes': 'for the test'},
        'votes': {'auth': 'for the test'},
      };

      final result = checkImports(root, graph: cyclic);

      expect(result.violations, hasLength(1));
      expect(
        result.violations.single.toString(),
        startsWith(
          'tool/check_imports.dart:1: featureGraph has a cycle: '
          'auth -> votes -> auth (',
        ),
      );
    });

    test('refuses a graph that depends on something that is no feature', () {
      write('lib/features/auth/domain/u.dart', '');
      const unknown = {
        'auth': {'ghost': 'for the test'},
      };

      final result = checkImports(root, graph: unknown);

      expect(
        result.violations.single.message,
        'featureGraph: auth depends on ghost, which is no feature',
      );
    });

    test('a test of a feature may not import the tests of another feature, '
        'only the support', () {
      write('test/support/builders/b.dart', '');
      write('test/features/votes/domain/helper.dart', '');
      write('test/features/auth/domain/helper.dart', '');
      write('test/features/votes/domain/a_test.dart', '''
import '../../../support/builders/b.dart';
import 'helper.dart';
import '../../auth/domain/helper.dart';
''');
      write('test/core/domain/c_test.dart', '''
import '../../features/votes/domain/helper.dart';
import '../../support/builders/b.dart';
''');

      expect(violationsAt(), [
        'test/core/domain/c_test.dart:1',
        'test/features/votes/domain/a_test.dart:3',
      ]);
      expect(messages().first, contains('test support is limited to'));
    });
  });

  group('the declared graph of the features', () {
    test('has no cycle', () {
      expect(
        findCycle({
          for (final MapEntry(:key, :value) in featureGraph.entries)
            key: value.keys,
        }),
        isNull,
      );
      expect(graphProblems(featureGraph), isEmpty);
    });

    test('is the graph of docs/architecture.md: auth below meetings, which '
        'documents and votes build on', () {
      expect(
        {
          for (final MapEntry(:key, :value) in featureGraph.entries)
            key: value.keys.toSet(),
        },
        {
          'auth': <String>{},
          'meetings': {'auth'},
          'documents': {'auth', 'meetings'},
          'votes': {'auth', 'meetings'},
        },
      );
    });

    test('says why each edge exists', () {
      for (final MapEntry(:key, value: edges) in featureGraph.entries) {
        for (final MapEntry(key: dependency, value: why) in edges.entries) {
          expect(why.trim(), isNotEmpty, reason: '$key -> $dependency');
        }
      }
    });
  });

  group('findCycle', () {
    test('finds none in a graph that points one way', () {
      expect(
        findCycle({
          'a': ['b', 'c'],
          'b': ['c'],
          'c': <String>[],
        }),
        isNull,
      );
    });

    test('finds a cycle between two nodes, and the path that closes it', () {
      expect(
        findCycle({
          'a': ['b'],
          'b': ['a'],
        }),
        ['a', 'b', 'a'],
      );
    });

    test('finds a longer cycle behind a node that is not part of it', () {
      expect(
        findCycle({
          'entry': ['a'],
          'a': ['b'],
          'b': ['c'],
          'c': ['a'],
        }),
        ['a', 'b', 'c', 'a'],
      );
    });

    test('finds a node that depends on itself', () {
      expect(
        findCycle({
          'a': ['a'],
        }),
        ['a', 'a'],
      );
    });

    test('does not mistake a node reached twice for a cycle', () {
      expect(
        findCycle({
          'a': ['b', 'c'],
          'b': ['d'],
          'c': ['d'],
          'd': <String>[],
        }),
        isNull,
      );
    });

    test('ignores a node that is no key of the graph', () {
      expect(
        findCycle({
          'a': ['ghost'],
        }),
        isNull,
      );
    });
  });

  group('entry point and localization', () {
    test('main.dart and lib/l10n may import anything in lib', () {
      write('lib/core/infrastructure/i.dart', '');
      write('lib/features/auth/presentation/p.dart', '');
      write('lib/core/domain/a.dart', '');
      write('lib/main.dart', '''
import 'package:flutter/widgets.dart';
import 'package:boardroom/core/infrastructure/i.dart';
import 'package:boardroom/features/auth/presentation/p.dart';
import 'package:boardroom/core/domain/a.dart';
''');
      write('lib/l10n/app_localizations.dart', '''
import 'dart:io';
import 'package:boardroom/core/domain/a.dart';
''');

      expect(checkImports(root).violations, isEmpty);
    });
  });

  group('lib/l10n', () {
    test('a hand-written file is outside the layers', () {
      write('lib/core/infrastructure/x.dart', '');
      write('lib/l10n/evil.dart', '''
import 'package:boardroom/core/infrastructure/x.dart';
''');
      write(
        'lib/features/auth/presentation/p.dart',
        "import '../../../l10n/evil.dart';\n",
      );

      expect(violationsAt(), [
        'lib/features/auth/presentation/p.dart:1',
        'lib/l10n/evil.dart:1',
      ]);
      expect(messages().last, contains('file outside the layers'));
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

    test('a file outside core/<layer>, features/<feature>/<layer> and app is '
        'a violation', () {
      write('lib/utils/helper.dart', '');
      write('lib/domain/old.dart', '');
      write('lib/core/foo/x.dart', '');
      write('lib/features/auth/x.dart', '');
      write('lib/features/auth/utils/y.dart', '');
      write('lib/core/domain/deep/ok.dart', '');
      write('lib/features/auth/domain/deep/ok.dart', '');
      write('lib/app/dev/ok.dart', '');

      expect(violationsAt(), [
        'lib/core/foo/x.dart:1',
        'lib/domain/old.dart:1',
        'lib/features/auth/utils/y.dart:1',
        'lib/features/auth/x.dart:1',
        'lib/utils/helper.dart:1',
      ]);
      expect(messages().first, contains('core/<layer>'));
      expect(messages().first, contains('features/<feature>/<layer>'));
    });

    test('a layer may not import a file that belongs to no layer', () {
      write('lib/utils/helper.dart', '');
      write(
        'lib/core/infrastructure/i.dart',
        "import '../../utils/helper.dart';\n",
      );

      expect(violationsAt(), [
        'lib/core/infrastructure/i.dart:1',
        'lib/utils/helper.dart:1',
      ]);
    });
  });

  group('generated files', () {
    test('are checked like their source', () {
      write('lib/core/domain/a.dart', "part 'a.freezed.dart';\n");
      write('lib/core/domain/a.freezed.dart', '''
part of 'a.dart';
''');
      write('lib/core/domain/b.g.dart', "import 'dart:io';\n");

      expect(violationsAt(), ['lib/core/domain/b.g.dart:1']);
    });
  });

  group('tests', () {
    test('test/features/<feature>/domain follows the domain rules plus '
        'package:test, the builders and its own folder', () {
      write('lib/core/domain/a.dart', '');
      write('lib/features/meetings/domain/m.dart', '');
      write('test/support/builders/builders.dart', '');
      write('test/features/auth/domain/helper.dart', '');
      write('test/features/auth/domain/a_test.dart', '''
import 'package:test/test.dart';
import 'package:boardroom/core/domain/a.dart';
import 'package:boardroom/features/meetings/domain/m.dart';
import '../../../../lib/core/domain/a.dart';
import '../../../support/builders/builders.dart';
import 'helper.dart';
import 'dart:async';
''');

      expect(checkImports(root).violations, isEmpty);
    });

    test(
      'test/core/domain may not import flutter_test, Flutter nor dart:io',
      () {
        write('test/core/domain/a_test.dart', '''
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'dart:io';
''');

        expect(violationsAt(), [
          'test/core/domain/a_test.dart:1',
          'test/core/domain/a_test.dart:2',
          'test/core/domain/a_test.dart:3',
        ]);
        expect(
          messages().first,
          contains('test/core/domain may not import package:flutter_test'),
        );
        expect(messages().first, contains('plain `dart test`'));
      },
    );

    test(
      'a domain test may not import the application nor other test folders',
      () {
        write('lib/core/application/u.dart', '');
        write('test/support/fakes/fakes.dart', '');
        write('test/features/auth/application/helper.dart', '');
        write('test/app/helper.dart', '');
        write('test/features/auth/domain/a_test.dart', '''
import 'package:boardroom/core/application/u.dart';
import '../../../support/fakes/fakes.dart';
import '../application/helper.dart';
import '../../../app/helper.dart';
''');

        expect(violationsAt(), [
          'test/features/auth/domain/a_test.dart:1',
          'test/features/auth/domain/a_test.dart:2',
          'test/features/auth/domain/a_test.dart:3',
          'test/features/auth/domain/a_test.dart:4',
        ]);
      },
    );

    test('an application test may use the domain, the application, the '
        'pure test support and its own folder', () {
      write('lib/core/domain/a.dart', '');
      write('lib/features/meetings/application/u.dart', '');
      write('test/support/builders/b.dart', '');
      write('test/support/contracts/c.dart', '');
      write('test/support/fakes/f.dart', '');
      write('test/features/votes/application/use_cases/votes_support.dart', '');
      write('test/features/votes/application/use_cases/u_test.dart', '''
import 'package:test/test.dart';
import 'package:boardroom/core/domain/a.dart';
import 'package:boardroom/features/meetings/application/u.dart';
import '../../../../support/builders/b.dart';
import '../../../../support/contracts/c.dart';
import '../../../../support/fakes/f.dart';
import 'votes_support.dart';
''');

      expect(checkImports(root).violations, isEmpty);
    });

    test('an application test and the pure test support may not import '
        'infrastructure nor flutter_test', () {
      write('lib/core/infrastructure/i.dart', '');
      write('test/features/auth/application/u_test.dart', '''
import 'package:boardroom/core/infrastructure/i.dart';
import 'package:flutter_test/flutter_test.dart';
''');
      write('test/support/fakes/f.dart', '''
import 'package:boardroom/core/infrastructure/i.dart';
import 'package:flutter_test/flutter_test.dart';
''');

      expect(violationsAt(), [
        'test/features/auth/application/u_test.dart:1',
        'test/features/auth/application/u_test.dart:2',
        'test/support/fakes/f.dart:1',
        'test/support/fakes/f.dart:2',
      ]);
    });

    test('the other test folders are free', () {
      write('lib/core/infrastructure/i.dart', '');
      for (final path in [
        'test/app/p_test.dart',
        'test/core/infrastructure/c_test.dart',
        'test/features/auth/infrastructure/a_test.dart',
        'test/support/infrastructure/world.dart',
      ]) {
        write(path, '''
import 'package:flutter_test/flutter_test.dart';
import 'package:boardroom/core/infrastructure/i.dart';
import 'dart:io';
''');
      }
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
      write('lib/core/domain/a.dart', "import 'dart:io';\n");
      final out = StringBuffer();

      final code = report(checkImports(root), out);

      expect(code, 1);
      expect(
        out.toString(),
        'lib/core/domain/a.dart:1: domain may not import dart:io '
        '(dart:io is tied to a platform; allowed: dart:async, '
        'dart:collection, dart:convert, dart:core, dart:math, '
        'dart:typed_data)\n',
      );
    });

    test('prints a one-line summary and exits 0 when everything holds', () {
      write('lib/core/domain/a.dart', '');
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
