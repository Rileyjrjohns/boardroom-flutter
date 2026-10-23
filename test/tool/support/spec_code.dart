// What the conformance test reads from the Dart code: the enumerations (an enum
// that implements `StableValue`, or a public list or set of stable strings),
// the numeric constants, the use case classes and the interfaces of the ports.
// The files are read with the parser of the analyzer (syntax only, no
// resolution), so nothing is imported and a library that does not compile yet
// cannot hide a difference.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

/// The generated files, never read: they hold no declaration of the contract.
const List<String> generatedSuffixes = ['.freezed.dart', '.g.dart'];

/// The name of the interface every enumeration of stable strings implements.
const String stableValueInterface = 'StableValue';

/// The name of the operation that makes a class a use case.
const String executeMethod = 'execute';

/// The members of an enumeration: the stable string of each, by member name.
typedef EnumMembers = Map<String, String>;

/// An enumeration of stable strings of the code.
final class Enumeration {
  /// Creates an enumeration.
  const new({required this.name, required this.file, required this.values});

  /// The name of the enum, or of the public list or set.
  final String name;

  /// The file that declares it, relative to the project root.
  final String file;

  /// The stable strings, in declaration order.
  final List<String> values;
}

/// An operation of a port: its name and its parameter names, in order.
final class Operation {
  /// Creates an operation.
  const new({required this.name, required this.parameters});

  /// The name of the method.
  final String name;

  /// The names of the parameters, positional, optional and named, in order.
  final List<String> parameters;
}

/// An interface of the ports folder that declares at least one method.
final class PortInterface {
  /// Creates a port.
  const new({required this.name, required this.operations});

  /// The name of the class.
  final String name;

  /// Its methods.
  final List<Operation> operations;
}

/// The folders under [root] that match [pattern], a path relative to [root]
/// with `/` separators in which a segment `*` stands for any one folder:
/// `lib/features/*/domain` is the `domain` folder of every feature. Sorted; a
/// pattern that matches nothing gives an empty list.
List<Directory> foldersMatching(Directory root, String pattern) {
  var matches = [root];
  for (final segment in pattern.split('/')) {
    matches = [
      for (final directory in matches)
        if (segment == '*')
          ...directory.listSync().whereType<Directory>()
        else if (Directory(p.join(directory.path, segment)).existsSync())
          Directory(p.join(directory.path, segment)),
    ];
  }
  return matches..sort((a, b) => a.path.compareTo(b.path));
}

/// The Dart files under the folders that match [patterns] (see
/// [foldersMatching]), the generated ones left out, sorted by path.
List<File> sourceFilesUnder(Directory root, Iterable<String> patterns) {
  return [
    for (final pattern in patterns)
      for (final directory in foldersMatching(root, pattern))
        for (final entity in directory.listSync(recursive: true))
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !generatedSuffixes.any(entity.path.endsWith))
            entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
}

CompilationUnit _unitOf(File file) => parseString(
  content: file.readAsStringSync(),
  path: file.path,
  throwIfDiagnostics: false,
).unit;

bool _isPublic(String name) => !name.startsWith('_');

/// `FOO_BAR` as `FooBar`: the Dart name of a constant of an `as const` object
/// that became an enum (docs/porting.md, section 4).
String pascalCaseOf(String upperSnake) => upperSnake
    .toLowerCase()
    .split('_')
    .where((word) => word.isNotEmpty)
    .map((word) => word[0].toUpperCase() + word.substring(1))
    .join();

/// `FOO_BAR` as `fooBar`: the Dart name of an exported constant that stays a
/// list, a set or a number (docs/porting.md, sections 2 and 4).
String camelCaseOf(String upperSnake) {
  final pascal = pascalCaseOf(upperSnake);
  return pascal.isEmpty
      ? pascal
      : pascal[0].toLowerCase() + pascal.substring(1);
}

/// The enums that implement `StableValue` in [files], by name. The stable
/// string of a member is its first argument, a string literal; a member
/// without argument stands for its own name.
Map<String, EnumMembers> enumMembersIn(Iterable<File> files) {
  final enums = <String, EnumMembers>{};
  for (final file in files) {
    for (final declaration in _unitOf(file).declarations) {
      if (declaration is! EnumDeclaration ||
          !_isPublic(declaration.namePart.typeName.lexeme)) {
        continue;
      }
      final implemented =
          declaration.implementsClause?.interfaces ?? const <NamedType>[];
      if (!implemented.any(
        (type) => type.name.lexeme == stableValueInterface,
      )) {
        continue;
      }
      enums[declaration.namePart.typeName.lexeme] = {
        for (final constant in declaration.body.constants)
          constant.name.lexeme: _stableString(constant),
      };
    }
  }
  return enums;
}

String _stableString(EnumConstantDeclaration constant) {
  final arguments = constant.arguments?.argumentList.arguments ?? [];
  final first = arguments.firstOrNull;
  return first is SimpleStringLiteral ? first.value : constant.name.lexeme;
}

final RegExp _enumValueAccess = RegExp(r'^(\w+)\.(\w+)\.value$');

/// The enumerations in [files]: the enums that implement `StableValue`, and the
/// public top-level lists and sets of stable strings (`Enum.member.value` of an
/// enum of [knownEnums], or a string literal), named in lowerCamelCase.
List<Enumeration> enumerationsIn(
  Directory root,
  Iterable<File> files,
  Map<String, EnumMembers> knownEnums,
) {
  final found = <Enumeration>[];
  for (final file in files) {
    final relative = p.relative(file.path, from: root.path);
    for (final declaration in _unitOf(file).declarations) {
      if (declaration is EnumDeclaration) {
        final members = knownEnums[declaration.namePart.typeName.lexeme];
        if (members != null &&
            _isPublic(declaration.namePart.typeName.lexeme)) {
          found.add(
            Enumeration(
              name: declaration.namePart.typeName.lexeme,
              file: relative,
              values: members.values.toList(),
            ),
          );
        }
      } else if (declaration is TopLevelVariableDeclaration) {
        for (final variable in declaration.variables.variables) {
          final name = variable.name.lexeme;
          final values = _stableStringsOf(variable.initializer, knownEnums);
          if (_isPublic(name) && values != null) {
            found.add(Enumeration(name: name, file: relative, values: values));
          }
        }
      }
    }
  }
  return found;
}

Expression? _firstExpression(ArgumentList arguments) {
  final first = arguments.arguments.firstOrNull;
  return first is Expression ? first : null;
}

/// The stable strings of a collection literal, possibly wrapped in a call
/// (`Set.unmodifiable({...})`), or `null` when the expression is anything else.
List<String>? _stableStringsOf(
  Expression? expression,
  Map<String, EnumMembers> knownEnums,
) {
  if (expression == null) {
    return null;
  }
  final List<CollectionElement> elements;
  if (expression is ListLiteral) {
    elements = expression.elements;
  } else if (expression is SetOrMapLiteral && !expression.isMap) {
    elements = expression.elements;
  } else if (expression is MethodInvocation) {
    return _stableStringsOf(
      _firstExpression(expression.argumentList),
      knownEnums,
    );
  } else if (expression is InstanceCreationExpression) {
    return _stableStringsOf(
      _firstExpression(expression.argumentList),
      knownEnums,
    );
  } else {
    return null;
  }
  if (elements.isEmpty) {
    return null;
  }
  final values = <String>[];
  for (final element in elements) {
    if (element is SimpleStringLiteral) {
      values.add(element.value);
      continue;
    }
    final access = _enumValueAccess.firstMatch(element.toSource());
    final value = access == null
        ? null
        : knownEnums[access.group(1)]?[access.group(2)];
    if (value == null) {
      return null;
    }
    values.add(value);
  }
  return values;
}

/// The public top-level `const int` constants of [files], by name.
Map<String, int> numericConstantsIn(Iterable<File> files) {
  final constants = <String, int>{};
  for (final file in files) {
    for (final declaration in _unitOf(file).declarations) {
      if (declaration is! TopLevelVariableDeclaration ||
          !declaration.variables.isConst) {
        continue;
      }
      for (final variable in declaration.variables.variables) {
        final initializer = variable.initializer;
        if (_isPublic(variable.name.lexeme) && initializer is IntegerLiteral) {
          constants[variable.name.lexeme] = initializer.value!;
        }
      }
    }
  }
  return constants;
}

/// The methods a class declares (no field, no constructor).
Iterable<MethodDeclaration> _methodsOf(ClassDeclaration declaration) {
  final body = declaration.body;
  return body is BlockClassBody
      ? body.members.whereType<MethodDeclaration>()
      : const [];
}

/// The names of the public classes of [files] that have an `execute` method,
/// sorted.
List<String> useCaseNamesIn(Iterable<File> files) {
  final names = <String>[];
  for (final file in files) {
    for (final declaration in _unitOf(file).declarations) {
      if (declaration is! ClassDeclaration ||
          !_isPublic(declaration.namePart.typeName.lexeme)) {
        continue;
      }
      final hasExecute = _methodsOf(declaration).any(
        (method) =>
            !method.isStatic &&
            !method.isGetter &&
            !method.isSetter &&
            method.name.lexeme == executeMethod,
      );
      if (hasExecute) {
        names.add(declaration.namePart.typeName.lexeme);
      }
    }
  }
  return names..sort();
}

/// The ports in [files]: the public `abstract interface class`es that declare
/// at least one method. The data-only classes of the folder (a cache entry, an
/// event) and the interfaces with getters only are not ports.
List<PortInterface> portsIn(Iterable<File> files) {
  final ports = <PortInterface>[];
  for (final file in files) {
    for (final declaration in _unitOf(file).declarations) {
      if (declaration is! ClassDeclaration ||
          !_isPublic(declaration.namePart.typeName.lexeme) ||
          declaration.abstractKeyword == null ||
          declaration.interfaceKeyword == null) {
        continue;
      }
      final operations = [
        for (final method in _methodsOf(declaration))
          if (!method.isStatic &&
              !method.isGetter &&
              !method.isSetter &&
              !method.isOperator)
            Operation(
              name: method.name.lexeme,
              parameters: [
                for (final parameter
                    in method.parameters?.parameters ??
                        const <FormalParameter>[])
                  parameter.name?.lexeme ?? '',
              ],
            ),
      ];
      if (operations.isNotEmpty) {
        ports.add(
          PortInterface(
            name: declaration.namePart.typeName.lexeme,
            operations: operations,
          ),
        );
      }
    }
  }
  return ports;
}
