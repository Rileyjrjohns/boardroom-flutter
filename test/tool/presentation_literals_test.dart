import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// The counterpart of the lint rule of the React Native app that forbids a
// literal text in the JSX: no user-facing string is written in the code of the
// presentation (`lib/core/presentation`, `lib/features/*/presentation`) nor in
// `lib/app`. Every text comes from the ARB files, through the generated
// `AppLocalizations`. The rule reads the code with the parser of the analyzer,
// so a comment or a string that is not a text (a key, a path, a test id) is not
// mistaken for one.

/// The widgets whose first positional argument is a text.
const Set<String> textWidgets = {'Text', 'SelectableText'};

/// The named arguments that hold a text the user reads or a screen reader says.
const Set<String> textArguments = {
  'title',
  'label',
  'labelText',
  'hint',
  'hintText',
  'helperText',
  'errorText',
  'message',
  'semanticsLabel',
  'semanticLabel',
  'tooltip',
  'text',
  'subtitle',
};

/// The folders of `lib/app` that are not the UI: the composition, the
/// simulated world, the database and the device build objects and talk to
/// servers, and the texts they hold (a JSON message, a log) are not shown.
const Set<String> nonUiAppFolders = {
  'composition',
  'container',
  'dev',
  'device',
  'persistence',
};

/// Folders (and files) whose code is checked.
const List<String> checkedFolders = [
  'lib/core/presentation',
  'lib/app',
  'lib/features',
];

/// A literal that is not a text: no letter in it (a separator, a space, an
/// ellipsis, a number).
final RegExp _hasLetter = RegExp(r'\p{L}', unicode: true);

/// A text literal found in a source: its line and its value.
typedef Finding = ({int line, String value});

/// The literal texts in [source], a Dart file.
List<Finding> literalTexts(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final visitor = _Visitor(parsed);
  parsed.unit.accept(visitor);
  return visitor.findings;
}

class _Visitor extends RecursiveAstVisitor<void> {
  new(this._parsed);

  final ParseStringResult _parsed;
  final List<Finding> findings = [];

  void _report(Expression expression) {
    if (expression is! StringLiteral) {
      return;
    }
    final value = expression is SimpleStringLiteral
        ? expression.value
        : expression.toSource();
    if (!_hasLetter.hasMatch(value)) {
      return;
    }
    findings.add((
      line: _parsed.lineInfo.getLocation(expression.offset).lineNumber,
      value: value,
    ));
  }

  void _check(String name, ArgumentList arguments) {
    var first = true;
    for (final argument in arguments.arguments) {
      if (argument is NamedArgument) {
        if (textArguments.contains(argument.name.lexeme)) {
          _report(argument.argumentExpression);
        }
      } else if (first &&
          textWidgets.contains(name) &&
          argument is Expression) {
        _report(argument);
      }
      first = false;
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node.methodName.name, node.argumentList);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node.constructorName.type.name.lexeme, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }
}

List<File> _checkedFiles() => [
  for (final folder in checkedFolders)
    for (final entity in Directory(folder).listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          !entity.path.endsWith('.g.dart') &&
          !entity.path.endsWith('.freezed.dart') &&
          (folder != 'lib/features' ||
              p.split(entity.path).contains('presentation')) &&
          (folder != 'lib/app' ||
              !nonUiAppFolders.contains(p.split(entity.path)[2])))
        entity,
];

void main() {
  group('literalTexts', () {
    test('finds a literal in a Text, and in the arguments that are texts', () {
      final findings = literalTexts(r'''
void f() {
  Text('Hello');
  const Text("Hello again");
  AppButton(title: 'Go', onPressed: null);
  Foo(label: 'Name', hint: 'Hint');
  Text('$name is here');
}
''');

      expect(findings.map((finding) => finding.line), [2, 3, 4, 5, 5, 6]);
    });

    test('lets a text from the localizations, a key and a symbol through', () {
      final findings = literalTexts('''
void f() {
  Text(l10n.title);
  Text('·');
  Text(' ');
  Foo(key: Key('sign-in-email'), path: '/sign-in');
  AppButton(title: l10n.go, onPressed: null);
  Text(message);
}
''');

      expect(findings, isEmpty);
    });
  });

  test('the presentation and the app hold no literal text', () {
    final found = <String>[];
    for (final file in _checkedFiles()) {
      for (final finding in literalTexts(file.readAsStringSync())) {
        found.add('${file.path}:${finding.line}: ${finding.value}');
      }
    }

    expect(found, isEmpty, reason: 'move these texts to the ARB files');
  });

  test('the checked folders hold code', () {
    expect(_checkedFiles().length, greaterThan(30));
  });
}
