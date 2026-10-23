import 'dart:io';
import 'dart:math' as math;

import 'package:boardroom/domain/entities/agenda_item.dart';
import 'package:boardroom/domain/entities/document.dart';
import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/domain/entities/participant.dart';
import 'package:boardroom/domain/entities/resolution.dart';
import 'package:boardroom/domain/entities/user.dart';
import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/document_location.dart';
import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:boardroom/domain/value_objects/email_address.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/domain/value_objects/page_cursor.dart';
import 'package:boardroom/domain/value_objects/page_request.dart';
import 'package:boardroom/domain/value_objects/vote_choice.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/spec_code.dart';
import 'support/spec_markdown.dart';

// The conformance test of the specification (docs/spec). The code follows the
// spec exactly, and this test fails when they diverge, in both directions:
// everything in the code is in the spec, and everything in the spec is in the
// code. It is the Dart counterpart of `tooling/spec.test.ts` of the React
// Native repository, for the domain, the use cases and the ports. How the files
// are read is documented in docs/spec/README.md ("Conformance conventions");
// `support/spec_markdown.dart` reads the Markdown and `support/spec_code.dart`
// reads the Dart code with the parser of the analyzer.
//
// The names of the code follow docs/porting.md: `VOTE_CHOICE` is the enum
// `VoteChoice`, `SESSION_ENDING_CODES` is the list `sessionEndingCodes`,
// `SESSION_CHECK_INTERVAL_MILLIS` is `sessionCheckIntervalMillis`. The
// operations and their parameters keep their names (lowerCamelCase).

/// Why the screens are not checked yet.
const String _screensOutOfScope =
    'The screens, the routes and the test ids are specified in screens.md and '
    'belong to the presentation layer, which is built from step 5; this test '
    'covers the domain, the use cases and the ports.';

/// Why the settings are not checked yet.
const String _settingsOutOfScope =
    'The settings are the defaults of the composition root (the React Native '
    'src/di/config.ts), which is built with the providers, after the '
    'infrastructure; this test covers the domain, the use cases and the ports.';

/// The part of the project the conformance test reads.
const String _specFolder = 'docs/spec';
const String _domainFolder = 'lib/domain';
const String _errorsFolder = 'lib/domain/errors';
const String _portsFolder = 'lib/application/ports';
const String _sharedFolder = 'lib/application/shared';
const String _useCasesFolder = 'lib/application/use_cases';

/// The suffix of the Dart enums of error codes.
const String _errorCodeSuffix = 'ErrorCode';

/// A string that is not an identifier in a cell: an operation without
/// parameters is written `-`.
const String _noParameters = '-';

/// The header of the column that lists the error codes of an operation.
const String _errorsColumn = 'Errors';

/// The label of the lines of a use case that cite its ports and its errors.
const String _portsLabel = 'Ports';
const String _errorsLabel = 'Errors';

final Directory _root = Directory.current;

SpecDocument _spec(String file) =>
    readSpecFile(p.join(_root.path, _specFolder, file));

List<File> _files(String folder) => sourceFilesUnder(_root, folder);

/// Fails with the two lists that differ, instead of a bare "not equal".
void expectSameSet(List<String> inCode, List<String> inSpec) {
  final duplicates = {
    for (final (index, item) in inSpec.indexed)
      if (inSpec.indexOf(item) != index) item,
  };
  expect(
    {
      'missingFromSpec':
          (inCode.where((item) => !inSpec.contains(item)).toList()..sort()),
      'notInCode': (inSpec.where((item) => !inCode.contains(item)).toList()
        ..sort()),
      'duplicatedInSpec': duplicates.toList()..sort(),
    },
    equals({
      'missingFromSpec': <String>[],
      'notInCode': <String>[],
      'duplicatedInSpec': <String>[],
    }),
  );
}

/// The subject of a table for a message, or a note that it has none.
String _subjectOf(SpecTable table) => table.subject ?? '(no subject)';

/// The one item of a list, or a failure that says there was not exactly one.
T only<T>(List<T> items, String what) {
  if (items.length != 1) {
    fail('Expected exactly one $what, found ${items.length}.');
  }
  return items.single;
}

/// The name of each parameter of a signature: `a: A, b?: B<C, D>` is `a`, `b`.
/// `-` is none.
List<String> parameterNames(String cell) {
  final signature = cell.replaceAll('`', '');
  if (signature.trim() == _noParameters) {
    return [];
  }
  final names = <String>[];
  var depth = 0;
  var current = StringBuffer();
  for (final char in signature.split('')) {
    if ('<([{'.contains(char)) {
      depth++;
    }
    if ('>)]}'.contains(char)) {
      depth--;
    }
    if (char == ',' && depth == 0) {
      names.add(current.toString());
      current = StringBuffer();
    } else {
      current.write(char);
    }
  }
  names.add(current.toString());
  return [
    for (final parameter in names)
      parameter.split(':').first.trim().replaceAll(RegExp(r'\?$'), ''),
  ];
}

void main() {
  final spec = (
    readme: _spec('README.md'),
    domain: _spec('domain.md'),
    useCases: _spec('use-cases.md'),
    ports: _spec('ports.md'),
    screens: _spec('screens.md'),
  );
  final specFiles = [
    spec.readme,
    spec.domain,
    spec.useCases,
    spec.ports,
    spec.screens,
  ];

  group('the reader of the specification files', () {
    const sample =
        '# Title\n'
        '\n'
        '### `CONSTANT` and more\n'
        '\n'
        '| Value | Meaning |\n'
        '| ----- | ------- |\n'
        r'| `one` | A \| B  |'
        '\n'
        '| `two` | Two     |\n'
        '\n'
        '| Other | Meaning |\n'
        '| ----- | ------- |\n'
        '| `x`   | not read, see [t](t.md) |\n'
        '\n'
        '```mermaid\n'
        '| Value | Not a table |\n'
        '```\n'
        '\n'
        'See [the doc](domain.md#limits) and `[not](a-link)`.';
    final document = parseSpecText('sample.md', sample);

    test('reads a checked table with the subject of its heading', () {
      final tables = document.tablesOfKind([TableKind.value]);

      final table = only(tables, 'checked table');

      expect(table.subject, equals('CONSTANT'));
      expect(table.identifiers, equals(['one', 'two']));
    });

    test('reads an escaped bar as a bar '
        'and leaves tables of other kinds unchecked', () {
      expect(splitRow(r'| `a` | A \| B |'), equals(['`a`', 'A | B']));
      expect(document.tables.where((table) => !table.checked), hasLength(1));
    });

    test(
      'skips fenced blocks, keeps them, and reads the links outside code',
      () {
        expect(document.fences, hasLength(1));
        expect(document.fences.single.language, equals('mermaid'));
        expect(document.fences.single.body, equals('| Value | Not a table |'));
        expect(document.fences.single.line, equals(14));
        expect(
          document.links.map((link) => link.target),
          equals(['t.md', 'domain.md#limits']),
        );
      },
    );

    test('reads the tokens between backticks and the anchors', () {
      expect(firstCode('a `b` and `c`'), equals('b'));
      expect(allCodes('a `b` and `c`'), equals(['b', 'c']));
      expect(
        slugOf('`ACCESS` - where the user stands'),
        equals('access---where-the-user-stands'),
      );
      expect(
        document.sectionLines(document.headings[1]),
        contains('| `two` | Two     |'),
      );
    });
  });

  group('the files of the specification', () {
    test('only have checked tables of a kind that belongs to them', () {
      const allowed = <String, List<String>>{
        TableKind.code: ['domain.md'],
        TableKind.value: [
          'domain.md',
          'use-cases.md',
          'ports.md',
          'screens.md',
        ],
        TableKind.limit: ['domain.md'],
        TableKind.useCase: ['use-cases.md'],
        TableKind.setting: ['use-cases.md'],
        TableKind.constant: ['use-cases.md'],
        TableKind.port: ['ports.md'],
        TableKind.operation: ['ports.md'],
        TableKind.route: ['screens.md'],
        TableKind.testId: ['screens.md'],
        TableKind.builder: ['screens.md'],
      };
      final misplaced = [
        for (final document in specFiles)
          for (final table in document.tablesOfKind(TableKind.all))
            if (!(allowed[table.kind] ?? []).contains(document.file))
              '${document.file}:${table.line} ${table.kind}',
      ];

      expect(misplaced, isEmpty);
    });

    test('give every row of a checked table an identifier in backticks', () {
      final missing = [
        for (final document in specFiles)
          for (final table in document.tablesOfKind(TableKind.all))
            for (final row in table.rows)
              if (firstCode(row.firstOrNull ?? '') == null)
                '${document.file}:${table.line} ${row.firstOrNull ?? ''}',
      ];

      expect(missing, isEmpty);
    });

    // The links that leave docs/spec (`../api.md`, `../adr`) point into the
    // documentation of the React Native repository, which this repository does
    // not hold: they are not followed.
    test('only link to files and headings that exist', () {
      final specDirectory = p.join(_root.path, _specFolder);
      final broken = <String>[];
      for (final document in specFiles) {
        for (final link in document.links) {
          if (RegExp(
            '^[a-z][a-z0-9+.-]*:',
            caseSensitive: false,
          ).hasMatch(link.target)) {
            continue;
          }
          final parts = link.target.split('#');
          final file = parts.first;
          final fragment = parts.length > 1 ? parts[1] : null;
          final target = file.isEmpty
              ? p.join(specDirectory, document.file)
              : p.normalize(p.join(specDirectory, file));
          if (!p.isWithin(specDirectory, target)) {
            continue;
          }
          final description = '${document.file}:${link.line} ${link.target}';
          final exists =
              File(target).existsSync() || Directory(target).existsSync();
          if (!exists) {
            broken.add(description);
          } else if (fragment != null && target.endsWith('.md')) {
            final slugs = readSpecFile(target).headings.map((h) => h.slug);
            if (!slugs.contains(fragment)) {
              broken.add(description);
            }
          }
        }
      }

      expect(broken, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Enumerations and error codes
  // -------------------------------------------------------------------------

  final knownEnums = enumMembersIn([
    ..._files('lib/domain'),
    ..._files('lib/application'),
  ]);
  final errorCodeEnumerations =
      enumerationsIn(_root, _files(_errorsFolder), knownEnums)
          .where((enumeration) => enumeration.name.endsWith(_errorCodeSuffix))
          .toList();
  final errorCodes = [
    for (final enumeration in errorCodeEnumerations) ...enumeration.values,
  ];

  /// Whether a table whose heading names [subject] documents the Dart
  /// enumeration [name].
  bool documents(String? subject, String name) =>
      subject != null &&
      (pascalCaseOf(subject) == name || camelCaseOf(subject) == name);

  group('the enumerations and the error codes', () {
    test('include the error codes of the domain', () {
      expect(errorCodeEnumerations.length, greaterThanOrEqualTo(8));
      expect(errorCodes.length, greaterThanOrEqualTo(30));
      expect(errorCodes.toSet(), hasLength(errorCodes.length));
    });

    final sources = <(SpecDocument, List<File>)>[
      (spec.domain, _files(_domainFolder)),
      (spec.ports, _files(_portsFolder)),
      (spec.useCases, [..._files(_sharedFolder), ..._files(_useCasesFolder)]),
    ];
    for (final (document, files) in sources) {
      group('documented in ${document.file}', () {
        final enumerations = enumerationsIn(_root, files, knownEnums);
        final tables = document.tablesOfKind([TableKind.code, TableKind.value]);

        test('has at least one constant to compare', () {
          expect(enumerations, isNotEmpty);
        });

        for (final enumeration in enumerations) {
          test('lists every value of ${enumeration.name}, and no other', () {
            final table = only([
              for (final candidate in tables)
                if (documents(candidate.subject, enumeration.name)) candidate,
            ], 'table under the heading of ${enumeration.name}');

            expectSameSet(enumeration.values, table.identifiers);
          });
        }

        test('has no table for a constant that does not exist', () {
          final names = [
            for (final enumeration in enumerations) enumeration.name,
          ];
          final unknown = [
            for (final table in tables)
              if (!names.any((name) => documents(table.subject, name)))
                '${document.file}:${table.line} ${_subjectOf(table)}',
          ];

          expect(unknown, isEmpty);
        });
      });
    }

    test('documents the error codes in tables of the kind `Code`', () {
      final codeTables = [
        for (final table in spec.domain.tablesOfKind([TableKind.code]))
          pascalCaseOf(table.subject ?? ''),
      ]..sort();
      final names = [
        for (final enumeration in errorCodeEnumerations) enumeration.name,
      ]..sort();

      expect(codeTables, equals(names));
    });

    test('documents the other enumerations of the domain '
        'in tables of the kind `Value`', () {
      final names = [
        for (final enumeration in enumerationsIn(
          _root,
          _files(_domainFolder),
          knownEnums,
        ))
          if (!enumeration.name.endsWith(_errorCodeSuffix)) enumeration.name,
      ]..sort();
      final valueTables = [
        for (final table in spec.domain.tablesOfKind([TableKind.value]))
          pascalCaseOf(table.subject ?? ''),
      ]..sort();

      expect(valueTables, equals(names));
    });
  });

  // -------------------------------------------------------------------------
  // Use cases
  // -------------------------------------------------------------------------

  group('the use cases', () {
    final inCode = useCaseNamesIn(_files(_useCasesFolder));
    final indexTables = spec.useCases.tablesOfKind([TableKind.useCase]);
    final inSpec = [for (final table in indexTables) ...table.identifiers];
    final portNames = [
      for (final port in portsIn(_files(_portsFolder))) port.name,
    ];

    test('are found in the code', () {
      expect(inCode.length, greaterThanOrEqualTo(15));
    });

    test('are the use case classes of lib/application/use_cases, '
        'no more, no fewer', () {
      expect(indexTables, hasLength(1));
      expectSameSet(inCode, inSpec);
    });

    for (final name in inCode) {
      group(name, () {
        final headings = [
          for (final candidate in spec.useCases.headings)
            if (candidate.subject == name) candidate,
        ];
        final section = headings.isEmpty
            ? <String>[]
            : spec.useCases.sectionLines(headings.first);
        List<String> lineOf(String label) => [
          for (final line in section)
            if (line.startsWith('- **$label**:')) line,
        ];

        test('has a section of its own', () {
          expect(headings, hasLength(1));
        });

        test('lists the ports it uses, and they are ports', () {
          final lines = lineOf(_portsLabel);
          final cited = lines.expand(allCodes).toList();

          expect(lines, hasLength(1));
          expect(cited.where((port) => !portNames.contains(port)), isEmpty);
          expect(
            lines.isEmpty ||
                cited.isNotEmpty ||
                RegExp('none', caseSensitive: false).hasMatch(lines.first),
            isTrue,
          );
        });

        test(
          'lists the error codes it can return, and they are error codes',
          () {
            final lines = lineOf(_errorsLabel);
            final cited = lines.expand(allCodes).toList();

            expect(lines, hasLength(1));
            expect(cited.where((code) => !errorCodes.contains(code)), isEmpty);
            expect(
              lines.isEmpty ||
                  cited.isNotEmpty ||
                  RegExp('none', caseSensitive: false).hasMatch(lines.first),
              isTrue,
            );
          },
        );
      });
    }
  });

  // -------------------------------------------------------------------------
  // Ports
  // -------------------------------------------------------------------------

  group('the ports', () {
    final inCode = portsIn(_files(_portsFolder));
    final indexTables = spec.ports.tablesOfKind([TableKind.port]);
    final operationTables = spec.ports.tablesOfKind([TableKind.operation]);

    test('are found in the code', () {
      expect(inCode.length, greaterThanOrEqualTo(10));
    });

    test('are the interfaces with operations of lib/application/ports, '
        'no more, no fewer', () {
      expect(indexTables, hasLength(1));
      expectSameSet(
        [for (final port in inCode) port.name],
        [for (final table in indexTables) ...table.identifiers],
      );
    });

    test('have no table of operations for something that is not a port', () {
      final names = [for (final port in inCode) port.name];

      expect([
        for (final table in operationTables)
          if (table.subject == null || !names.contains(table.subject))
            'ports.md:${table.line} ${_subjectOf(table)}',
      ], isEmpty);
    });

    for (final port in inCode) {
      group(port.name, () {
        final tables = [
          for (final table in operationTables)
            if (table.subject == port.name) table,
        ];

        test('has one table of operations', () {
          expect(tables, hasLength(1));
        });

        test('lists every operation of the interface, and no other', () {
          expectSameSet(
            [for (final operation in port.operations) operation.name],
            [for (final table in tables) ...table.identifiers],
          );
        });

        for (final operation in port.operations) {
          test('gives the parameters of ${operation.name} '
              'in the order of the code', () {
            final rows = [for (final table in tables) ...table.rows];
            final row = rows
                .where(
                  (candidate) =>
                      firstCode(candidate.firstOrNull ?? '') == operation.name,
                )
                .firstOrNull;

            expect(
              parameterNames(
                row != null && row.length > 1 ? row[1] : '(no row)',
              ),
              equals(operation.parameters),
            );
          });
        }

        test('cites only error codes that exist', () {
          final header = tables.firstOrNull?.header ?? <String>[];
          final column = header.indexOf(_errorsColumn);
          final cited = [
            for (final row in tables.firstOrNull?.rows ?? <List<String>>[])
              ...allCodes(
                column >= 0 && column < row.length ? row[column] : '',
              ),
          ];

          expect(column, greaterThan(0));
          expect(cited.where((code) => !errorCodes.contains(code)), isEmpty);
        });
      });
    }
  });

  // -------------------------------------------------------------------------
  // Screens: routes, test ids, builders, navigation map
  // -------------------------------------------------------------------------

  group('the routes', () {
    test('are the screen files of the presentation layer', () {
      fail(_screensOutOfScope);
    });
  }, skip: _screensOutOfScope);

  group('the test ids', () {
    test('are the values of the test ids of the presentation layer', () {
      fail(_screensOutOfScope);
    });
  }, skip: _screensOutOfScope);

  group('the test id builders', () {
    test('are the builder functions of the test ids', () {
      fail(_screensOutOfScope);
    });
  }, skip: _screensOutOfScope);

  // -------------------------------------------------------------------------
  // Limits, settings and constants
  // -------------------------------------------------------------------------

  String text(int length) => 'a' * length;
  final userId = _unwrap(parseUserId('u'));
  final meetingId = _unwrap(parseMeetingId('m'));
  final documentId = _unwrap(parseDocumentId('d'));
  final resolutionId = _unwrap(parseResolutionId('r'));
  final agendaItemId = _unwrap(parseAgendaItemId('a'));
  final email = _unwrap(parseEmailAddress('a@b.co'));
  final instant = _unwrap(parseInstant(0));
  final vote = createVote(
    VoteInput(
      resolutionId: resolutionId,
      meetingId: meetingId,
      voterId: userId,
      choice: VoteChoice.forChoice,
      castAt: instant,
    ),
  );

  /// For each limit of the spec, whether the code accepts a value of that size.
  final probes = <String, bool Function(int)>{
    'identifier': (size) => [
      parseUserId,
      parseMeetingId,
      parseAgendaItemId,
      parseResolutionId,
      parseDocumentId,
    ].every((parse) => isOk(parse(text(size)))),
    'email': (size) =>
        isOk(parseEmailAddress('${text(math.max(size - 5, 0))}@b.co')),
    'fullName': (size) =>
        isOk(createUser(id: userId, fullName: text(size), email: email)) &&
        isOk(
          createParticipant(
            userId: userId,
            fullName: text(size),
            role: ParticipantRole.member,
          ),
        ),
    'title': (size) =>
        isOk(
          createDocument(
            DocumentInput(
              id: documentId,
              title: text(size),
              confidentiality: ConfidentialityLevel.public,
              pageCount: 1,
            ),
          ),
        ) &&
        isOk(
          createMeetingSummary(
            MeetingSummaryInput(
              id: meetingId,
              title: text(size),
              scheduledAt: instant,
              location: 'x',
            ),
          ),
        ) &&
        isOk(
          createResolution(
            ResolutionInput(
              id: resolutionId,
              title: text(size),
              description: 'x',
              status: ResolutionStatus.open,
            ),
          ),
        ) &&
        isOk(
          createAgendaItem(
            AgendaItemInput(id: agendaItemId, position: 1, title: text(size)),
          ),
        ),
    'description': (size) =>
        isOk(
          createResolution(
            ResolutionInput(
              id: resolutionId,
              title: 'x',
              description: text(size),
              status: ResolutionStatus.open,
            ),
          ),
        ) &&
        // An agenda item may have no description (a blank one is none): its
        // maximum is the same.
        (size == 0 ||
            isOk(
              createAgendaItem(
                AgendaItemInput(
                  id: agendaItemId,
                  position: 1,
                  title: 'x',
                  description: text(size),
                ),
              ),
            )),
    'meetingLocation': (size) => isOk(
      createMeetingSummary(
        MeetingSummaryInput(
          id: meetingId,
          title: 'x',
          scheduledAt: instant,
          location: text(size),
        ),
      ),
    ),
    'pageCursor': (size) => isOk(parsePageCursor(text(size))),
    'documentLocation': (size) => isOk(parseDocumentLocation(text(size))),
    'pageCount': (size) => isOk(
      createDocument(
        DocumentInput(
          id: documentId,
          title: 'x',
          confidentiality: ConfidentialityLevel.public,
          pageCount: size,
        ),
      ),
    ),
    'agendaPosition': (size) => isOk(
      createAgendaItem(
        AgendaItemInput(id: agendaItemId, position: size, title: 'x'),
      ),
    ),
    'pageLimit': (size) => isOk(createPageRequest(limit: size)),
    'attemptCount': (size) => isOk(
      restorePendingVote(vote: vote, enqueuedAt: instant, attempts: size),
    ),
    'duration': (size) => isOk(durationFromMillis(size)),
    'instant': (size) => isOk(parseInstant(size)),
  };

  /// A number written in a cell of the spec, with or without separators.
  int? numberIn(String cell) {
    final digits = cell.replaceAll(RegExp('[^0-9]'), '');
    return digits.isEmpty ? null : int.parse(digits);
  }

  group('the limits', () {
    final tables = spec.domain.tablesOfKind([TableKind.limit]);
    final rows = [for (final table in tables) ...table.rows];

    test('are probed one by one', () {
      expect(tables, hasLength(1));
      expectSameSet(probes.keys.toList(), [
        for (final row in rows) firstCode(row.first) ?? '',
      ]);
    });

    for (final row in rows) {
      final name = firstCode(row.first) ?? '';
      test('has the bounds of $name in the code', () {
        final probe = probes[name];
        final min = numberIn(row.length > 1 ? row[1] : '');
        final max = numberIn(row.length > 2 ? row[2] : '');

        expect(probe, isNotNull);
        if (probe == null || max == null) {
          fail('No bounds for $name');
        }
        expect(probe(max), isTrue);
        expect(probe(max + 1), isFalse);
        if (min != null) {
          expect(probe(min), isTrue);
          if (min > 0) {
            expect(probe(min - 1), isFalse);
          }
        }
      });
    }
  });

  group('the settings', () {
    test('have the default value in the composition root', () {
      fail(_settingsOutOfScope);
    });
  }, skip: _settingsOutOfScope);

  group('the constants of the application', () {
    final inCode = numericConstantsIn(_files(_sharedFolder));
    final tables = spec.useCases.tablesOfKind([TableKind.constant]);
    final rows = [for (final table in tables) ...table.rows];

    test('are the numeric constants of lib/application/shared, '
        'no more, no fewer', () {
      expect(tables, hasLength(1));
      expectSameSet(inCode.keys.toList(), [
        for (final row in rows) camelCaseOf(firstCode(row.first) ?? ''),
      ]);
    });

    for (final row in rows) {
      final name = camelCaseOf(firstCode(row.first) ?? '');
      test('has the value of $name in the code', () {
        expect(
          '${inCode[name]}',
          equals((row.length > 1 ? row[1] : '').replaceAll('`', '').trim()),
        );
      });
    }
  });
}

/// The value of a success; a failure is a broken probe.
T _unwrap<T, E>(Result<T, E> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => throw StateError('Unexpected failure: $error'),
};
