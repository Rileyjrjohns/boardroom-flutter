import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/scenario_parity.dart';
import '../../tool/ts_test_names.dart';

// Pure Dart: these tests build small throwaway trees (a React Native tree and
// a Flutter project) in a temp folder and run the checker on them, so every
// rule is exercised in both directions without touching the real repositories.
// The last group runs the whole command line on such a pair of trees.

void main() {
  late Directory rn;
  late Directory project;

  setUp(() {
    final temp = Directory.systemTemp.createTempSync('scenario_parity_test_');
    rn = Directory(p.join(temp.path, 'rn'))..createSync();
    project = Directory(p.join(temp.path, 'app'))..createSync();
  });

  tearDown(() {
    rn.parent.deleteSync(recursive: true);
  });

  /// Writes [content] to [path] of the throwaway React Native tree.
  void writeRn(String path, String content) {
    File(p.joinAll([rn.path, ...path.split('/')]))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// The full names of the tests of a React Native test file.
  List<String> names(String path) => [
    for (final test in extractTsTests(path, root: rn)) test.displayName,
  ];

  group('the names of the React Native tests', () {
    test('joins the titles of the describe calls and of the test', () {
      writeRn('src/domain/a.test.ts', '''
describe('Result', () => {
  it('builds', () => {});
  describe('map', () => {
    it('transforms', () => {});
    test('keeps a failure', async () => {});
  });
});
it('top level', () => {});
''');

      expect(names('src/domain/a.test.ts'), [
        'Result builds',
        'Result map transforms',
        'Result map keeps a failure',
        'top level',
      ]);
    });

    test('is not fooled by strings, comments, regular expressions', () {
      writeRn('src/domain/a.test.ts', r'''
// it('commented out', () => {});
/* describe('also commented', () => { it('x', () => {}); }); */
describe('braces } and { in text', () => {
  const pattern = /it\('no'\)|}/g;
  const half = 10 / 2;
  it("quote ' and `tick` and ${'dollar'}", () => {
    const text = "it('inside a string', () => {})";
    expect(text).toMatch(pattern);
  });
  it('after the regex', () => {});
});
''');

      expect(names('src/domain/a.test.ts'), [
        r"braces } and { in text quote ' and `tick` and ${'dollar'}",
        'braces } and { in text after the regex',
      ]);
    });

    test('computes template literals, concatenations and constants', () {
      writeRn('src/domain/a.test.ts', r'''
const SIZE = 3;
const NAME = 'list';
describe(`the ${NAME} of ${SIZE * 2} items`, () => {
  it('a ' + 'b' + ` c${SIZE}`, () => {});
  it(`unknown ${compute()}`, () => {});
});
''');

      final tests = extractTsTests('src/domain/a.test.ts', root: rn);

      expect(tests.map((test) => test.displayName), [
        'the list of 6 items a b c3',
        'the list of 6 items unknown *',
      ]);
      expect(tests[1].hasWildcard, isTrue);
      expect(
        tests[1].pattern.hasMatch('the list of 6 items unknown 12'),
        isTrue,
      );
      expect(
        tests[1].pattern.hasMatch('the list of 7 items unknown 12'),
        isFalse,
      );
    });

    test('marks the skipped and the todo tests, and keeps their names', () {
      writeRn('src/domain/a.test.ts', '''
describe.skip('all skipped', () => { it('one', () => {}); });
describe('some', () => {
  it.skip('skipped', () => {});
  xit('x-skipped', () => {});
  it.todo('to do');
  it.only('only', () => {});
  it('plain', () => {});
});
''');

      final tests = extractTsTests('src/domain/a.test.ts', root: rn);

      expect(
        {for (final test in tests) test.displayName: test.skipped},
        {
          'all skipped one': true,
          'some skipped': true,
          'some x-skipped': true,
          'some to do': true,
          'some only': false,
          'some plain': false,
        },
      );
    });

    test('expands it.each like jest-each: %s, %j, %p, %d, %i, %#, %%', () {
      writeRn('src/domain/a.test.ts', r'''
describe('each', () => {
  it.each(['a', 'b'])('string %s', () => {});
  it.each(['', '\n\t', 'café', '\ud800'])('json %j', () => {});
  it.each([1.5, Number.NaN, Number.POSITIVE_INFINITY, -1, 0])('number %p', () => {});
  it.each([undefined, 'x'])('maybe %j and %s', () => {});
  it.each([['one', 1], ['two', 2]])('row %s is %d (%#) 100%%', () => {});
  it.each<[string, number]>([['x', 7]])('typed %s %i', () => {});
  it.each([{ code: 'a', n: 1 }, { n: 2, code: 'b' }])('object %p', () => {});
  it.each([[1, 2], [3, 4]])('array row %p %p', () => {});
  it.each([[1, 2, 3]])('more values %s', () => {});
  it.each([['a']])('fewer values %s %s', () => {});
  it.each([[null, true]])('null %s bool %p %s', () => {});
  it.each([[[1, 2], { a: [1] }]])('nested %p and %j', () => {});
});
''');

      expect(names('src/domain/a.test.ts'), [
        'each string a',
        'each string b',
        'each json ""',
        r'each json "\n\t"',
        'each json "café"',
        r'each json "\ud800"',
        'each number 1.5',
        'each number NaN',
        'each number Infinity',
        'each number -1',
        'each number 0',
        'each maybe undefined and %s',
        'each maybe "x" and %s',
        'each row one is 1 (0) 100%',
        'each row two is 2 (1) 100%',
        'each typed x 7',
        'each object {"code": "a", "n": 1}',
        'each object {"code": "b", "n": 2}',
        'each array row 1 2',
        'each array row 3 4',
        'each more values 1',
        'each fewer values a %s',
        'each null null bool true %s',
        'each nested [1, 2] and {"a":[1]}',
      ]);
    });

    test('expands describe.each and binds the parameters of its callback', () {
      writeRn('src/domain/a.test.ts', r'''
const PARSERS = [
  ['user id', parseUserId, 'userId'],
  ['meeting id', parseMeetingId, 'meetingId'],
] as const;
describe.each(PARSERS)('the %s', (name, parse, field) => {
  it(`names ${field} for ${name}`, () => {});
  it.each(['', ' '])('rejects %j', () => {});
});
''');

      expect(names('src/domain/a.test.ts'), [
        'the user id names userId for user id',
        'the user id rejects ""',
        'the user id rejects " "',
        'the meeting id names meetingId for meeting id',
        'the meeting id rejects ""',
        'the meeting id rejects " "',
      ]);
    });

    test('follows Object.values and valuesOf into an imported constant', () {
      writeRn('src/domain/Period.ts', '''
export const PERIOD = { Upcoming: 'upcoming', Past: 'past' } as const;
''');
      writeRn('src/domain/a.test.ts', '''
import { PERIOD } from './Period';
import { valuesOf } from './shared/constants';

describe('Period', () => {
  it.each(Object.values(PERIOD))('parses %s', () => {});
  it.each(valuesOf(PERIOD))('lists %s', () => {});
  it.each([...Object.values(PERIOD), 'extra'])('spreads %s', () => {});
});
''');

      expect(names('src/domain/a.test.ts'), [
        'Period parses upcoming',
        'Period parses past',
        'Period lists upcoming',
        'Period lists past',
        'Period spreads upcoming',
        'Period spreads past',
        'Period spreads extra',
      ]);
    });

    test('resolves the aliases of the imports', () {
      writeRn('src/domain/Period.ts', "export const PERIOD = ['a', 'b'];\n");
      writeRn('src/application/a.test.ts', '''
import { PERIOD } from '@domain/Period';

describe.each(PERIOD)('from %s', () => { it('works', () => {}); });
''');

      expect(names('src/application/a.test.ts'), [
        'from a works',
        'from b works',
      ]);
    });

    test('evaluates a function of the project whose body is one return', () {
      writeRn('src/domain/errors.ts', '''
export const CODE = { Network: 'networkUnavailable', Other: 'unexpected' } as const;
export function networkUnavailable() {
  return { code: CODE.Network };
}
export function unexpected(cause?: string) {
  return cause === undefined ? { code: CODE.Other } : { code: CODE.Other, cause };
}
''');
      writeRn('src/domain/a.test.ts', '''
import { networkUnavailable, unexpected } from './errors';

it.each([networkUnavailable(), unexpected(), unexpected('HTTP 500')])('rejects %p', () => {});
''');

      expect(names('src/domain/a.test.ts'), [
        'rejects {"code": "networkUnavailable"}',
        'rejects {"code": "unexpected"}',
        'rejects {"cause": "HTTP 500", "code": "unexpected"}',
      ]);
    });

    test('leaves a wildcard where it cannot compute a value', () {
      writeRn('src/domain/a.test.ts', '''
describe('unknown', () => {
  it.each([build(1), build(2)])('row %s', () => {});
  it.each(table())('rows of %s', () => {});
});
''');

      final tests = extractTsTests('src/domain/a.test.ts', root: rn);

      expect(tests.map((test) => test.displayName), [
        'unknown row *',
        'unknown row *',
        'unknown rows of *',
      ]);
      expect(tests.every((test) => test.hasWildcard), isTrue);
    });

    test(
      'expands the contract suites a test file calls, with their arguments',
      () {
        writeRn('src/application/testing/contracts/xContract.ts', r'''
export interface Options { readonly enabled: boolean }

export function describeXContract(name: string, make: () => number, options: Options): void {
  describe(`${name} honours the X contract`, () => {
    it('does a thing', () => {});
    (options.enabled ? describe : describe.skip)('the optional part', () => {
      it('does another', () => {});
    });
  });
}
''');
        writeRn('src/application/testing/a.contracts.test.ts', '''
import { describeXContract } from './contracts/xContract';

describeXContract('FakeX', () => 1, { enabled: true });
describeXContract('RealX', () => 2, { enabled: false });
''');

        expect(names('src/application/testing/a.contracts.test.ts'), [
          'FakeX honours the X contract does a thing',
          'FakeX honours the X contract the optional part does another',
          'RealX honours the X contract does a thing',
          'RealX honours the X contract the optional part does another',
        ]);
      },
    );

    test('returns nothing for a file that does not exist', () {
      expect(names('src/domain/missing.test.ts'), isEmpty);
    });
  });

  group('the Dart file of a React Native test file', () {
    final cases = {
      'src/domain/shared/Result.test.ts':
          'test/core/domain/shared/result_test.dart',
      'src/domain/value-objects/EmailAddress.test.ts':
          'test/features/auth/domain/value_objects/email_address_test.dart',
      'src/domain/policies/appLock.test.ts':
          'test/features/auth/domain/policies/app_lock_test.dart',
      'src/application/shared/appLock.test.ts':
          'test/features/auth/application/session/app_lock_test.dart',
      'src/application/use-cases/auth/SignIn.test.ts':
          'test/features/auth/application/use_cases/sign_in_test.dart',
      'src/application/shared/ScreenProtectionCoordinator.test.ts':
          'test/features/documents/application/'
          'screen_protection_coordinator_test.dart',
      'src/application/testing/fakes.contracts.test.ts':
          'test/support/fakes/fakes_contracts_test.dart',
      'src/application/testing/fakes.test.ts':
          'test/support/fakes/fakes_test.dart',
      'src/application/securityScenarios.test.ts':
          'test/core/application/security_scenarios_test.dart',
    };
    final dartTestFiles = [
      ...cases.values,
      'test/core/domain/limits_test.dart',
      'test/core/domain/literals_test.dart',
      'test/core/application/literals_test.dart',
    ];

    for (final MapEntry(key: rnPath, value: dartPath) in cases.entries) {
      test('$rnPath is $dartPath', () {
        expect(dartTestPathFor(rnPath, dartTestFiles), dartPath);
      });
    }

    test('is none for what is not a test of the domain or the application', () {
      expect(dartTestPathFor('src/domain/shared/Result.ts', const []), isNull);
      expect(dartTestPathFor('src/infrastructure/x.test.ts', const []), isNull);
      expect(dartTestPathFor('tooling/spec.test.ts', const []), isNull);
    });

    test('has a folder prefix for --only', () {
      const valueObject =
          'test/features/auth/domain/value_objects/email_address_test.dart';
      const fake = 'test/support/fakes/fakes_test.dart';
      const useCase = 'test/features/auth/application/use_cases/x_test.dart';
      expect(dartFileMatchesPrefix(valueObject, 'src/domain'), isTrue);
      expect(
        dartFileMatchesPrefix(valueObject, 'src/domain/value-objects'),
        isTrue,
      );
      expect(dartFileMatchesPrefix(valueObject, 'src/domain/shared'), isFalse);
      expect(dartFileMatchesPrefix(valueObject, 'src/application'), isFalse);
      expect(dartFileMatchesPrefix(fake, 'src/application'), isTrue);
      expect(dartFileMatchesPrefix(fake, 'src/application/testing'), isTrue);
      expect(dartFileMatchesPrefix(fake, 'src/domain'), isFalse);
      expect(dartFileMatchesPrefix(useCase, 'src/application'), isTrue);
      expect(dartFileMatchesPrefix(useCase, 'docs'), isFalse);
    });

    test('is a path that stands for the file when no file has the name', () {
      expect(
        dartTestPathFor('src/domain/shared/Gone.test.ts', dartTestFiles),
        'test/**/gone_test.dart',
      );
    });

    test('refuses to guess between files of the same name and layer', () {
      expect(
        () => dartTestPathFor('src/domain/shared/Result.test.ts', [
          'test/features/a/domain/result_test.dart',
          'test/features/b/domain/result_test.dart',
        ]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('result_test.dart'), contains('features/a')),
          ),
        ),
      );
    });

    test('snake-cases a name', () {
      expect(snakeCase('FooBar'), 'foo_bar');
      expect(snakeCase('fooBar2Baz'), 'foo_bar2_baz');
      expect(snakeCase('URLParser'), 'url_parser');
      expect(snakeCase('use-cases'), 'use_cases');
      expect(snakeCase('fakes.contracts'), 'fakes_contracts');
    });
  });

  group('the notes of docs/parity', () {
    test('reads the rows of a table', () {
      final notes = parseParityNotes(r'''
# Title

| File | Test | Reason |
| ---- | ---- | ------ |
| `src/domain/a.test.ts` | `a b c` | type level |
| `src/domain/a.test.ts` | `has \| a bar` | one more |
| `src/domain/a.test.ts` | ``has a ` tick`` | with a backtick |
| not a row | ignored | ignored |
''');

      expect(
        [for (final note in notes) (note.file, note.test, note.reason)],
        [
          ('src/domain/a.test.ts', 'a b c', 'type level'),
          ('src/domain/a.test.ts', 'has | a bar', 'one more'),
          ('src/domain/a.test.ts', 'has a ` tick', 'with a backtick'),
        ],
      );
    });
  });

  group('the Dart tests that dart test reports', () {
    String event(Map<String, Object?> fields) => jsonEncode(fields);

    test('reads the names by file, without the loading and hidden tests', () {
      final output = [
        'Running somewhere...',
        event({
          'type': 'suite',
          'suite': {'id': 0, 'path': 'test/core/domain/a_test.dart'},
        }),
        event({
          'type': 'testStart',
          'test': {
            'id': 1,
            'name': 'loading test/core/domain/a_test.dart',
            'suiteID': 0,
          },
        }),
        event({
          'type': 'testDone',
          'testID': 1,
          'result': 'success',
          'hidden': true,
        }),
        event({
          'type': 'testStart',
          'test': {'id': 2, 'name': 'group first', 'suiteID': 0},
        }),
        event({
          'type': 'testDone',
          'testID': 2,
          'result': 'success',
          'hidden': false,
        }),
        event({
          'type': 'testStart',
          'test': {'id': 3, 'name': '(setUpAll)', 'suiteID': 0},
        }),
        event({
          'type': 'testDone',
          'testID': 3,
          'result': 'success',
          'hidden': true,
        }),
        event({
          'type': 'testStart',
          'test': {'id': 4, 'name': 'group skipped', 'suiteID': 0},
        }),
        event({
          'type': 'testDone',
          'testID': 4,
          'result': 'success',
          'skipped': true,
          'hidden': false,
        }),
        '{"broken json',
      ].join('\n');

      final report = parseDartTestEvents(output);

      expect(report.tests, {
        'test/core/domain/a_test.dart': ['group first', 'group skipped'],
      });
      expect(report.loadErrors, isEmpty);
    });

    test('reports the files that do not load', () {
      final output = [
        event({
          'type': 'suite',
          'suite': {'id': 0, 'path': 'test/core/domain/a_test.dart'},
        }),
        event({
          'type': 'testStart',
          'test': {
            'id': 1,
            'name': 'loading test/core/domain/a_test.dart',
            'suiteID': 0,
          },
        }),
        event({
          'type': 'testDone',
          'testID': 1,
          'result': 'error',
          'hidden': true,
        }),
      ].join('\n');

      expect(parseDartTestEvents(output).loadErrors, [
        'test/core/domain/a_test.dart',
      ]);
    });
  });

  group('compareScenarios', () {
    TsTest rnTest(String name) => TsTest([name]);

    ParityNote note(String file, String test) =>
        ParityNote(file: file, test: test, reason: 'because');

    const rnFile = 'src/domain/shared/Result.test.ts';
    const dartFile = 'test/core/domain/shared/result_test.dart';

    test('is fine when every scenario has a Dart test of the same name', () {
      final report = compareScenarios(
        rnTests: {
          rnFile: [rnTest('Result a'), rnTest('Result b'), rnTest('Result b')],
        },
        dartTests: {
          dartFile: ['Result b', 'Result a', 'Result b'],
        },
      );

      expect(report.ok, isTrue);
      expect(report.rnCount, 3);
      expect(report.dartCount, 3);
    });

    test('reports a scenario with no Dart test, and a name that differs', () {
      final report = compareScenarios(
        rnTests: {
          rnFile: [rnTest('Result a'), rnTest('Result b')],
        },
        dartTests: {
          dartFile: ['Result a', 'Result B'],
        },
      );

      expect(report.ok, isFalse);
      expect(report.files.single.missing, ['Result b']);
      expect(report.files.single.extra, ['Result B']);
    });

    test('counts a repeated name as many times as it is repeated', () {
      final report = compareScenarios(
        rnTests: {
          rnFile: [rnTest('same'), rnTest('same')],
        },
        dartTests: {
          dartFile: ['same'],
        },
      );

      expect(report.files.single.missing, ['same']);
    });

    test('reports a Dart file with no test at all', () {
      final report = compareScenarios(
        rnTests: {
          rnFile: [rnTest('a')],
        },
        dartTests: const {},
      );

      expect(report.files.single.dartFileExists, isFalse);
      expect(report.files.single.missing, ['a']);
    });

    test('does not expect an excepted scenario', () {
      final report = compareScenarios(
        rnTests: {
          rnFile: [rnTest('a'), rnTest('type level')],
        },
        dartTests: {
          dartFile: ['a'],
        },
        exceptions: [note(rnFile, 'type level')],
      );

      expect(report.ok, isTrue);
      expect(report.files.single.excepted, ['type level']);
    });

    test('refuses an exception that is stale or not needed', () {
      final report = compareScenarios(
        rnTests: {
          rnFile: [rnTest('a'), rnTest('b')],
        },
        dartTests: {
          dartFile: ['a', 'b'],
        },
        exceptions: [note(rnFile, 'b'), note(rnFile, 'gone')],
      );

      final file = report.files.single;
      expect(report.ok, isFalse);
      expect(file.staleExceptions.single, contains('gone'));
      expect(file.problems.single, contains('not needed'));
    });

    test(
      'refuses a Dart test with no scenario unless extras.md explains it',
      () {
        final unexplained = compareScenarios(
          rnTests: {
            rnFile: [rnTest('a')],
          },
          dartTests: {
            dartFile: ['a', 'only in Dart'],
          },
        );
        final explained = compareScenarios(
          rnTests: {
            rnFile: [rnTest('a')],
          },
          dartTests: {
            dartFile: ['a', 'only in Dart'],
          },
          extras: [note(dartFile, 'only in Dart')],
        );

        expect(unexplained.files.single.extra, ['only in Dart']);
        expect(explained.ok, isTrue);
      },
    );

    test('refuses an extras entry that matches no Dart test', () {
      final report = compareScenarios(
        rnTests: {
          rnFile: [rnTest('a')],
        },
        dartTests: {
          dartFile: ['a'],
        },
        extras: [note(dartFile, 'gone')],
      );

      expect(report.ok, isFalse);
      expect(report.files.single.staleExceptions.single, contains('gone'));
    });

    test('checks the Dart files that no React Native file maps to', () {
      const extraFile = 'test/core/domain/shared/trim_text_test.dart';
      final unexplained = compareScenarios(
        rnTests: const {},
        dartTests: {
          extraFile: ['trims'],
        },
      );
      final explained = compareScenarios(
        rnTests: const {},
        dartTests: {
          extraFile: ['trims', 'and more'],
        },
        extras: [note(extraFile, '*')],
      );

      expect(unexplained.ok, isFalse);
      expect(explained.ok, isTrue);
    });

    test(
      'matches a name with a wildcard by pattern, one test per scenario',
      () {
        const wildcard = TsTest(['rejects ', Wildcard.instance, ' now']);
        final report = compareScenarios(
          rnTests: {
            rnFile: [wildcard, wildcard],
          },
          dartTests: {
            dartFile: ['rejects x now', 'rejects y now'],
          },
        );
        final tooFew = compareScenarios(
          rnTests: {
            rnFile: [wildcard, wildcard],
          },
          dartTests: {
            dartFile: ['rejects x now'],
          },
        );

        expect(report.ok, isTrue);
        expect(tooFew.files.single.missing, ['rejects * now']);
      },
    );

    test('restricts the comparison to the folders given to --only', () {
      final report = compareScenarios(
        rnTests: {
          rnFile: [rnTest('a')],
          'src/domain/value-objects/Page.test.ts': [rnTest('b')],
        },
        dartTests: {
          'test/core/domain/value_objects/page_test.dart': ['b'],
          'test/core/domain/shared/other_test.dart': ['stranger'],
        },
        only: ['src/domain/value-objects'],
      );

      expect(report.ok, isTrue);
      expect(report.files.map((file) => file.rnFile), [
        'src/domain/value-objects/Page.test.ts',
      ]);
    });

    test('reports a Dart file that does not load', () {
      final report = compareScenarios(
        rnTests: {
          rnFile: [rnTest('a')],
        },
        dartTests: {
          dartFile: ['a'],
        },
        dartLoadErrors: {dartFile},
      );

      expect(report.ok, isFalse);
      expect(report.files.single.problems.single, contains('does not load'));
    });

    test('writes the report and the table of the use cases', () {
      const useCase = 'src/application/use-cases/auth/SignIn.test.ts';
      final report = compareScenarios(
        rnTests: {
          rnFile: [rnTest('a')],
          useCase: [rnTest('x'), rnTest('y')],
        },
        dartTests: {
          dartFile: ['a'],
          'test/features/auth/application/use_cases/sign_in_test.dart': ['x'],
        },
      );

      expect(
        renderReport(report),
        allOf(
          contains(
            'FAIL 1/2  $useCase -> test/features/auth/application/use_cases/sign_in_test.dart',
          ),
          contains('missing in Dart: y'),
          contains('ok   1/1  $rnFile -> $dartFile'),
          contains(
            '2 files, 3 React Native scenarios, 2 Dart tests, '
            '1 with differences.',
          ),
        ),
      );
      expect(
        renderUseCaseTable(report),
        contains(
          '| SignIn | `$useCase` | `test/features/auth/application/use_cases/sign_in_test.dart` '
          '| 2 | 1 | 1 missing, 0 extra |',
        ),
      );
    });
  });

  group('the command line', () {
    const rnTestPath = 'src/domain/shared/Result.test.ts';
    const dartTestPath = 'test/core/domain/shared/result_test.dart';

    String events(Map<String, List<String>> tests) {
      final lines = <String>[];
      var id = 0;
      var suite = 0;
      for (final MapEntry(:key, :value) in tests.entries) {
        lines.add(
          jsonEncode({
            'type': 'suite',
            'suite': {'id': suite, 'path': key},
          }),
        );
        for (final name in value) {
          id++;
          lines
            ..add(
              jsonEncode({
                'type': 'testStart',
                'test': {'id': id, 'name': name, 'suiteID': suite},
              }),
            )
            ..add(
              jsonEncode({
                'type': 'testDone',
                'testID': id,
                'result': 'success',
                'hidden': false,
              }),
            );
        }
        suite++;
      }
      return lines.join('\n');
    }

    Future<(int, String, String)> run(
      List<String> args,
      Map<String, List<String>> dartTests,
    ) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runScenarioParity(
        ['--root', project.path, ...args],
        out: out,
        err: err,
        runner: (_) async => events(dartTests),
      );
      return (code, out.toString(), err.toString());
    }

    setUp(() {
      writeRn(
        rnTestPath,
        "describe('Result', () => { it('a', () => {}); });\n",
      );
    });

    test('exits with 0 when every scenario is in Dart', () async {
      final (code, out, _) = await run(
        ['--rn', rn.path],
        {
          dartTestPath: ['Result a'],
        },
      );

      expect(code, 0);
      expect(out, contains('ok   1/1'));
    });

    test('exits with 1 on a difference, and honours --only', () async {
      writeRn(
        'src/domain/value-objects/Page.test.ts',
        "it('page', () => {});\n",
      );

      final (code, out, _) = await run(
        ['--rn', rn.path, '--only', 'src/domain/shared'],
        {
          dartTestPath: ['Result b'],
        },
      );
      final (codeOther, outOther, _) = await run(
        ['--rn', rn.path, '--only', 'src/domain/shared'],
        {
          dartTestPath: ['Result a'],
        },
      );

      expect(code, 1);
      expect(out, contains('missing in Dart: Result a'));
      expect(out, isNot(contains('Page.test.ts')));
      expect(codeOther, 0);
      expect(outOther, isNot(contains('Page.test.ts')));
    });

    test('reads docs/parity/exceptions.md and docs/parity/extras.md', () async {
      File(p.join(project.path, exceptionsFile))
        ..createSync(recursive: true)
        ..writeAsStringSync('| `$rnTestPath` | `Result a` | type level |\n');
      File(p.join(project.path, extrasFile))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '| `$dartTestPath` | `Result extra` | Dart only |\n',
        );

      final (code, _, _) = await run(
        ['--rn', rn.path],
        {
          dartTestPath: ['Result extra'],
        },
      );

      expect(code, 0);
    });

    test('prints the table of the use cases', () async {
      writeRn(
        'src/application/use-cases/auth/SignIn.test.ts',
        "describe('SignIn', () => { it('a', () => {}); });\n",
      );

      final (code, out, _) = await run(
        ['--rn', rn.path, '--table', '--only', 'src/application'],
        {
          'test/features/auth/application/use_cases/sign_in_test.dart': [
            'SignIn a',
          ],
        },
      );

      expect(code, 0);
      expect(out, contains('| SignIn |'));
      expect(out, contains('identical'));
    });

    test('compares with the names of a jest --json report', () async {
      final jest = File(p.join(rn.parent.path, 'jest.json'))
        ..writeAsStringSync(
          jsonEncode({
            'testResults': [
              {
                'name': p.join(rn.path, rnTestPath),
                'assertionResults': [
                  {'fullName': 'Result from jest', 'status': 'passed'},
                ],
              },
            ],
          }),
        );

      final (code, _, _) = await run(
        ['--rn', rn.path, '--rn-names', jest.path],
        {
          dartTestPath: ['Result from jest'],
        },
      );

      expect(code, 0);
    });

    test('exits with 2 when it cannot run', () async {
      final (noRn, _, errNoRn) = await run([], {});
      final (notRn, _, errNotRn) = await run(['--rn', project.path], {});
      final (unknown, _, errUnknown) = await run(['--nope'], {});
      final (twoFiles, _, errTwoFiles) = await run(
        ['--rn', rn.path],
        {
          'test/features/a/domain/shared/result_test.dart': ['Result a'],
          'test/features/b/domain/shared/result_test.dart': ['Result a'],
        },
      );

      expect((noRn, notRn, unknown, twoFiles), (2, 2, 2, 2));
      expect(errNoRn, contains('--rn is required'));
      expect(errNotRn, contains('not a checkout'));
      expect(errUnknown, contains('unknown option'));
      expect(errTwoFiles, contains('several Dart test files'));
    });
  });
}
