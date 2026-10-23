// Reads the names of the tests of a TypeScript (Jest) test file, without
// running Jest and without a TypeScript compiler.
//
// tool/scenario_parity.dart uses it to list the scenarios of the React Native
// repository. The file is cut into tokens (strings, template literals,
// comments and regular expressions are skipped properly, so that a brace in a
// string cannot fool the nesting), then the calls of `describe`, `it`, `test`
// and their `.each` forms are found. The title of a test is an expression, so
// a small evaluator computes it: literals, template literals, constants of the
// file or of the files it imports, `Object.values(...)`, spreads, casts. What
// it cannot compute (a call of a function of the project, for example) becomes
// a wildcard in the name, and the caller matches such a name with a pattern
// instead of an exact string.
//
// The expansion of `it.each` follows jest-each: `%s`, `%p`, `%j`, `%d`, `%i`,
// `%f`, `%#` and `%%` are replaced with the values of the row, in order. The
// names are the "full names" of Jest: the titles of the enclosing `describe`
// calls and of the test, joined with one space.
//
// Contract suites (a function of a support file that calls `describe` and `it`,
// and that a test file calls) are expanded in place, with their parameters
// bound to the arguments of the call.
import 'dart:io';

import 'package:path/path.dart' as p;

/// A part of a name that could not be computed. It stands for any text.
class Wildcard {
  const new _();

  /// The only instance.
  static const Wildcard instance = Wildcard._();

  @override
  String toString() => '*';
}

/// One test of a file: its full name, in parts. A part is a [String] or a
/// [Wildcard].
class TsTest {
  /// Creates a test from the parts of its full name.
  const new(this.parts, {this.skipped = false});

  /// The pieces of the full name, in order.
  final List<Object> parts;

  /// Whether the test is skipped (`it.skip`, `xit`, `describe.skip`,
  /// `it.todo`).
  final bool skipped;

  /// Whether some part of the name is a wildcard.
  bool get hasWildcard => parts.any((part) => part is Wildcard);

  /// The full name, with `*` for every wildcard.
  String get displayName => parts.map((part) => '$part').join();

  /// A regular expression that matches the full names this test can have.
  RegExp get pattern {
    final source = parts
        .map((part) => part is String ? RegExp.escape(part) : r'[\s\S]*')
        .join();
    return RegExp('^$source\$');
  }

  @override
  String toString() => displayName;
}

/// The tests of the file at [path], with their full names. Paths use `/`.
///
/// [root] is the root of the repository, to resolve the imports of the file
/// (`./x`, `../x` and the aliases of `tsconfig.json` written in [aliases]).
List<TsTest> extractTsTests(
  String path, {
  required Directory root,
  Map<String, String> aliases = const {
    '@core/': 'src/core/',
    '@features/': 'src/features/',
    '@composition/': 'src/composition/',
    '@testing/': 'src/testing/',
  },
}) {
  final project = _Project(root, aliases);
  final file = project.file(path);
  if (file == null) {
    return const [];
  }
  final out = <TsTest>[];
  _Scanner(project).scanRange(
    file,
    0,
    file.tokens.length,
    _Scope(file: file, parent: null),
    const [],
    out,
    0,
  );
  return out;
}

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

enum _Kind { identifier, number, string, template, punctuation, regex }

class _Token {
  new(this.kind, this.text, {this.value, this.parts});

  final _Kind kind;
  final String text;

  /// The decoded value of a string literal.
  final String? value;

  /// The parts of a template literal: a [String] (cooked text) or a
  /// `List<_Token>` (the tokens of a `${...}`).
  final List<Object>? parts;

  /// Index of the matching bracket, for `( [ {` and `) ] }`.
  int match = -1;

  bool isPunct(String text) => kind == _Kind.punctuation && this.text == text;

  bool isIdent([String? name]) =>
      kind == _Kind.identifier && (name == null || text == name);

  @override
  String toString() => text;
}

const Set<String> _keywordsBeforeRegex = {
  'return',
  'typeof',
  'case',
  'in',
  'of',
  'delete',
  'void',
  'throw',
  'new',
  'else',
  'do',
  'await',
  'yield',
};

class _Tokenizer {
  new(this.source);

  final String source;
  int pos = 0;

  /// Tokens up to the end of the source, or up to the `}` that closes a `${`.
  List<_Token> tokenize({bool untilCloseBrace = false}) {
    final tokens = <_Token>[];
    var depth = 0;
    while (pos < source.length) {
      final char = source[pos];
      if (_isSpace(char)) {
        pos++;
        continue;
      }
      if (source.startsWith('//', pos)) {
        final end = source.indexOf('\n', pos);
        pos = end < 0 ? source.length : end + 1;
        continue;
      }
      if (source.startsWith('/*', pos)) {
        final end = source.indexOf('*/', pos + 2);
        pos = end < 0 ? source.length : end + 2;
        continue;
      }
      if (untilCloseBrace && char == '}' && depth == 0) {
        pos++;
        return tokens;
      }
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
      }
      if (_isIdentStart(char)) {
        final start = pos;
        while (pos < source.length && _isIdentPart(source[pos])) {
          pos++;
        }
        tokens.add(_Token(_Kind.identifier, source.substring(start, pos)));
      } else if (_isDigit(char) ||
          (char == '.' &&
              pos + 1 < source.length &&
              _isDigit(source[pos + 1]))) {
        tokens.add(_readNumber());
      } else if (char == "'" || char == '"') {
        tokens.add(_readString(char));
      } else if (char == '`') {
        tokens.add(_readTemplate());
      } else if (char == '/' && _regexAllowed(tokens)) {
        tokens.add(_readRegex());
      } else {
        tokens.add(_readPunctuation());
      }
    }
    return tokens;
  }

  bool _regexAllowed(List<_Token> tokens) {
    if (tokens.isEmpty) {
      return true;
    }
    final last = tokens.last;
    return switch (last.kind) {
      _Kind.identifier => _keywordsBeforeRegex.contains(last.text),
      _Kind.number || _Kind.string || _Kind.template || _Kind.regex => false,
      _Kind.punctuation =>
        !(last.text == ')' || last.text == ']' || last.text == '}'),
    };
  }

  _Token _readPunctuation() {
    for (final operator in const [
      '...',
      '=>',
      '?.',
      '??',
      '===',
      '!==',
      '==',
      '!=',
    ]) {
      if (source.startsWith(operator, pos)) {
        pos += operator.length;
        return _Token(_Kind.punctuation, operator);
      }
    }
    return _Token(_Kind.punctuation, source[pos++]);
  }

  _Token _readNumber() {
    final start = pos;
    if (source[pos] == '0' &&
        pos + 1 < source.length &&
        'xXbBoO'.contains(source[pos + 1])) {
      pos += 2;
      while (pos < source.length &&
          RegExp('[0-9a-fA-F_]').hasMatch(source[pos])) {
        pos++;
      }
    } else {
      while (pos < source.length && RegExp('[0-9_.]').hasMatch(source[pos])) {
        // `1..toString()` and member access on a number are not used in tests.
        pos++;
      }
      if (pos < source.length && 'eE'.contains(source[pos])) {
        pos++;
        if (pos < source.length && '+-'.contains(source[pos])) {
          pos++;
        }
        while (pos < source.length && _isDigit(source[pos])) {
          pos++;
        }
      }
    }
    if (pos < source.length && source[pos] == 'n') {
      pos++;
    }
    return _Token(_Kind.number, source.substring(start, pos));
  }

  _Token _readString(String quote) {
    final start = pos;
    pos++;
    final out = StringBuffer();
    while (pos < source.length && source[pos] != quote) {
      if (source[pos] == r'\') {
        _readEscape(out);
      } else {
        out.write(source[pos++]);
      }
    }
    pos++;
    return _Token(
      _Kind.string,
      source.substring(start, pos > source.length ? source.length : pos),
      value: out.toString(),
    );
  }

  _Token _readTemplate() {
    final start = pos;
    pos++;
    final parts = <Object>[];
    final text = StringBuffer();
    while (pos < source.length && source[pos] != '`') {
      if (source[pos] == r'\') {
        _readEscape(text);
      } else if (source.startsWith(r'${', pos)) {
        parts.add(text.toString());
        text.clear();
        pos += 2;
        parts.add(_matched(tokenize(untilCloseBrace: true)));
      } else {
        text.write(source[pos++]);
      }
    }
    pos++;
    parts.add(text.toString());
    return _Token(
      _Kind.template,
      source.substring(start, pos > source.length ? source.length : pos),
      parts: parts,
    );
  }

  _Token _readRegex() {
    final start = pos;
    pos++;
    var inClass = false;
    while (pos < source.length) {
      final char = source[pos];
      if (char == r'\') {
        pos += 2;
        continue;
      }
      if (char == '[') {
        inClass = true;
      } else if (char == ']') {
        inClass = false;
      } else if (char == '/' && !inClass) {
        break;
      } else if (char == '\n') {
        break;
      }
      pos++;
    }
    pos++;
    while (pos < source.length && _isIdentPart(source[pos])) {
      pos++;
    }
    return _Token(_Kind.regex, source.substring(start, pos));
  }

  /// Reads the escape sequence at [pos] (a backslash) and writes what it
  /// stands for.
  void _readEscape(StringBuffer out) {
    pos++;
    if (pos >= source.length) {
      return;
    }
    final char = source[pos++];
    switch (char) {
      case 'n':
        out.write('\n');
      case 't':
        out.write('\t');
      case 'r':
        out.write('\r');
      case 'b':
        out.write('\b');
      case 'f':
        out.write('\f');
      case 'v':
        out.write('\v');
      case '0':
        out.write('\u0000');
      case 'x':
        out.writeCharCode(int.parse(source.substring(pos, pos + 2), radix: 16));
        pos += 2;
      case 'u':
        if (source[pos] == '{') {
          final end = source.indexOf('}', pos);
          final codePoint = int.parse(
            source.substring(pos + 1, end),
            radix: 16,
          );
          out.write(String.fromCharCode(codePoint));
          pos = end + 1;
        } else {
          out.writeCharCode(
            int.parse(source.substring(pos, pos + 4), radix: 16),
          );
          pos += 4;
        }
      case '\n':
        break;
      default:
        out.write(char);
    }
  }
}

/// Links every bracket of [tokens] (and of the `${}` inside templates) to its
/// partner.
List<_Token> _matched(List<_Token> tokens) {
  final stack = <int>[];
  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    if (token.kind == _Kind.template) {
      for (final part in token.parts!) {
        if (part is List<_Token>) {
          _matched(part);
        }
      }
    }
    if (token.kind != _Kind.punctuation) {
      continue;
    }
    switch (token.text) {
      case '(' || '[' || '{':
        stack.add(index);
      case ')' || ']' || '}':
        if (stack.isNotEmpty) {
          final open = stack.removeLast();
          tokens[open].match = index;
          token.match = open;
        }
    }
  }
  return tokens;
}

bool _isSpace(String char) =>
    char == ' ' ||
    char == '\n' ||
    char == '\t' ||
    char == '\r' ||
    char == ' ' ||
    char == '﻿';

bool _isDigit(String char) =>
    char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;

bool _isIdentStart(String char) => RegExp(r'[A-Za-z_$]').hasMatch(char);

bool _isIdentPart(String char) => RegExp(r'[A-Za-z0-9_$]').hasMatch(char);

// ---------------------------------------------------------------------------
// Files and scopes
// ---------------------------------------------------------------------------

class _ImportRef {
  const new(this.path, this.exportedName);

  final String path;
  final String exportedName;
}

class _Declaration {
  const new(this.start, this.end);

  final int start;
  final int end;
}

class _FunctionDeclaration {
  const new(this.parameters, this.bodyStart, this.bodyEnd);

  final List<String> parameters;
  final int bodyStart;
  final int bodyEnd;
}

class _SourceFile {
  new(this.path, this.tokens);

  final String path;
  final List<_Token> tokens;
  final Map<String, _ImportRef> imports = {};
  final Map<String, _Declaration> constants = {};
  final Map<String, _FunctionDeclaration> functions = {};
}

class _Project {
  new(this.root, this.aliases);

  final Directory root;
  final Map<String, String> aliases;
  final Map<String, _SourceFile?> _files = {};

  _SourceFile? file(String path) {
    return _files.putIfAbsent(path, () {
      final file = File(p.joinAll([root.path, ...path.split('/')]));
      if (!file.existsSync()) {
        return null;
      }
      final tokens = _matched(_Tokenizer(file.readAsStringSync()).tokenize());
      final source = _SourceFile(path, tokens);
      _readTopLevel(source, this);
      return source;
    });
  }

  /// The project-relative path of the module imported as [specifier] from the
  /// file at [from], or null when it is a package.
  String? resolve(String specifier, String from) {
    String? base;
    if (specifier.startsWith('.')) {
      base = p.posix.normalize(p.posix.join(p.posix.dirname(from), specifier));
    } else {
      for (final MapEntry(:key, :value) in aliases.entries) {
        if (specifier.startsWith(key)) {
          base = '$value${specifier.substring(key.length)}';
        }
      }
    }
    if (base == null) {
      return null;
    }
    for (final candidate in [
      '$base.ts',
      '$base.tsx',
      '$base/index.ts',
      '$base/index.tsx',
      base,
    ]) {
      if (File(p.joinAll([root.path, ...candidate.split('/')])).existsSync() &&
          FileSystemEntity.isFileSync(
            p.joinAll([root.path, ...candidate.split('/')]),
          )) {
        return candidate;
      }
    }
    return null;
  }
}

/// Fills the imports, the constants and the functions declared at the top level
/// of [source].
void _readTopLevel(_SourceFile source, _Project project) {
  final tokens = source.tokens;
  var index = 0;
  while (index < tokens.length) {
    final token = tokens[index];
    if (token.isIdent('import')) {
      index = _readImport(source, project, index);
      continue;
    }
    if (token.isIdent('function') ||
        (token.isIdent('async') &&
            index + 1 < tokens.length &&
            tokens[index + 1].isIdent('function'))) {
      final functionIndex = token.isIdent('async') ? index + 1 : index;
      final declaration = _readFunction(tokens, functionIndex);
      if (declaration != null) {
        source.functions[declaration.$1] = declaration.$2;
        index = declaration.$2.bodyEnd + 1;
        continue;
      }
    }
    if ((token.isIdent('const') ||
            token.isIdent('let') ||
            token.isIdent('var')) &&
        index + 1 < tokens.length &&
        tokens[index + 1].kind == _Kind.identifier) {
      final name = tokens[index + 1].text;
      final end = _statementEnd(tokens, index + 2, tokens.length);
      final equals = _findAssignment(tokens, index + 2, end);
      if (equals != null) {
        source.constants[name] = _Declaration(equals + 1, end);
      }
      index = end;
      continue;
    }
    // Skip a block we do not read, so that its content is not taken for the top
    // level.
    if ((token.isPunct('{') || token.isPunct('(') || token.isPunct('[')) &&
        token.match > index) {
      index = token.match + 1;
      continue;
    }
    index++;
  }
}

/// `function name(params) { body }` at [index] (the `function` keyword).
(String, _FunctionDeclaration)? _readFunction(List<_Token> tokens, int index) {
  var cursor = index + 1;
  if (cursor < tokens.length && tokens[cursor].isPunct('*')) {
    cursor++;
  }
  if (cursor >= tokens.length || tokens[cursor].kind != _Kind.identifier) {
    return null;
  }
  final name = tokens[cursor].text;
  cursor++;
  // Generic parameters.
  if (cursor < tokens.length && tokens[cursor].isPunct('<')) {
    cursor = _skipAngles(tokens, cursor);
  }
  if (cursor >= tokens.length || !tokens[cursor].isPunct('(')) {
    return null;
  }
  final parametersEnd = tokens[cursor].match;
  final parameters = _parameterNames(tokens, cursor + 1, parametersEnd);
  cursor = parametersEnd + 1;
  while (cursor < tokens.length && !tokens[cursor].isPunct('{')) {
    if (tokens[cursor].isPunct(';')) {
      return null;
    }
    if ((tokens[cursor].isPunct('(') || tokens[cursor].isPunct('[')) &&
        tokens[cursor].match > cursor) {
      cursor = tokens[cursor].match;
    }
    cursor++;
  }
  if (cursor >= tokens.length) {
    return null;
  }
  return (
    name,
    _FunctionDeclaration(parameters, cursor + 1, tokens[cursor].match),
  );
}

/// The index after the `>` that closes the `<` at [index].
int _skipAngles(List<_Token> tokens, int index) {
  var depth = 0;
  var cursor = index;
  while (cursor < tokens.length) {
    final token = tokens[cursor];
    if (token.isPunct('<')) {
      depth++;
    } else if (token.isPunct('>')) {
      depth--;
      if (depth == 0) {
        return cursor + 1;
      }
    } else if ((token.isPunct('(') ||
            token.isPunct('[') ||
            token.isPunct('{')) &&
        token.match > cursor) {
      cursor = token.match;
    }
    cursor++;
  }
  return cursor;
}

/// The names of the parameters in `tokens[start, end)`, `_` for a pattern.
List<String> _parameterNames(List<_Token> tokens, int start, int end) {
  final names = <String>[];
  var cursor = start;
  while (cursor < end) {
    final stop = _argumentEnd(tokens, cursor, end);
    var first = cursor;
    while (first < stop &&
        (tokens[first].isIdent('readonly') || tokens[first].isPunct('.'))) {
      first++;
    }
    names.add(
      first < stop && tokens[first].kind == _Kind.identifier
          ? tokens[first].text
          : '_',
    );
    cursor = stop + 1;
  }
  return names;
}

/// The index of the comma that ends the argument starting at [start], or [end].
int _argumentEnd(List<_Token> tokens, int start, int end) {
  var cursor = start;
  while (cursor < end) {
    final token = tokens[cursor];
    if (token.isPunct(',')) {
      return cursor;
    }
    if ((token.isPunct('(') || token.isPunct('[') || token.isPunct('{')) &&
        token.match > cursor) {
      cursor = token.match;
    } else if (token.isPunct('<') &&
        cursor > start &&
        tokens[cursor - 1].kind == _Kind.identifier) {
      // A generic argument list may hold commas: `Map<string, number>`.
      final after = _skipAngles(tokens, cursor);
      if (after < end &&
          (tokens[after].isPunct('(') ||
              tokens[after].isPunct(',') ||
              tokens[after].isPunct(')'))) {
        cursor = after - 1;
      }
    }
    cursor++;
  }
  return end;
}

/// The index of the `;` (or of the end of the statement) that ends the
/// declaration whose tokens start at [start].
int _statementEnd(List<_Token> tokens, int start, int end) {
  var cursor = start;
  while (cursor < end) {
    final token = tokens[cursor];
    if (token.isPunct(';')) {
      return cursor;
    }
    if ((token.isPunct('(') || token.isPunct('[') || token.isPunct('{')) &&
        token.match > cursor) {
      cursor = token.match;
    } else if (token.kind == _Kind.identifier &&
        const {
          'const',
          'let',
          'var',
          'function',
          'export',
          'import',
          'describe',
          'it',
          'test',
        }.contains(token.text) &&
        cursor > start &&
        tokens[cursor - 1].kind != _Kind.punctuation) {
      // A statement without a semicolon ended before this keyword.
      return cursor;
    }
    cursor++;
  }
  return end;
}

/// The index of the `=` of a declaration, skipping a type annotation.
int? _findAssignment(List<_Token> tokens, int start, int end) {
  var cursor = start;
  while (cursor < end) {
    final token = tokens[cursor];
    if (token.isPunct('=')) {
      return cursor;
    }
    if ((token.isPunct('(') || token.isPunct('[') || token.isPunct('{')) &&
        token.match > cursor) {
      cursor = token.match;
    }
    cursor++;
  }
  return null;
}

int _readImport(_SourceFile source, _Project project, int index) {
  final tokens = source.tokens;
  var cursor = index + 1;
  final names = <(String, String)>[]; // local, exported
  String? from;
  var end = cursor;
  while (end < tokens.length && !tokens[end].isPunct(';')) {
    if (tokens[end].isIdent('from') &&
        end + 1 < tokens.length &&
        tokens[end + 1].kind == _Kind.string) {
      from = tokens[end + 1].value;
      end += 2;
      break;
    }
    end++;
    if (end < tokens.length &&
        tokens[end].kind == _Kind.string &&
        end == cursor + 0) {
      break;
    }
  }
  if (from != null) {
    // `import type { A } from` carries no value.
    if (!tokens[cursor].isIdent('type')) {
      while (cursor < end) {
        final token = tokens[cursor];
        if (token.isPunct('{')) {
          var inner = cursor + 1;
          while (inner < token.match) {
            if (tokens[inner].isIdent('type')) {
              inner++;
            }
            final exported = tokens[inner].text;
            var local = exported;
            if (inner + 2 < token.match + 1 &&
                tokens[inner + 1].isIdent('as')) {
              local = tokens[inner + 2].text;
              inner += 2;
            }
            names.add((local, exported));
            inner++;
            if (inner < token.match && tokens[inner].isPunct(',')) {
              inner++;
            }
          }
          cursor = token.match + 1;
          continue;
        }
        cursor++;
      }
    }
    final path = project.resolve(from, source.path);
    if (path != null) {
      for (final (local, exported) in names) {
        source.imports[local] = _ImportRef(path, exported);
      }
    }
  }
  if (end < tokens.length && tokens[end].isPunct(';')) {
    end++;
  }
  return end;
}

class _Scope {
  new({required this.file, required this.parent});

  final _SourceFile file;
  final _Scope? parent;
  final Map<String, Object?> values = {};
  final Map<String, _Declaration> declarations = {};
  final Map<String, Object?> _cache = {};
}

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

/// A value the evaluator could not compute.
class _Unknown {
  const new();
}

const _Unknown _unknown = _Unknown();

/// The JavaScript `null`. The Dart `null` is `undefined`.
class _JsNull {
  const new();
}

const _JsNull _jsNull = _JsNull();

/// A string made of known and unknown parts.
class _Text {
  new(this.parts);

  final List<Object> parts;
}

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

class _Evaluator {
  new(
    this.project,
    this.scope,
    this.tokens,
    this.pos,
    this.end, [
    this.depth = 0,
  ]);

  final _Project project;
  final _Scope scope;
  final List<_Token> tokens;
  int pos;
  final int end;
  final int depth;

  static Object? evaluate(
    _Project project,
    _Scope scope,
    List<_Token> tokens,
    int start,
    int end, [
    int depth = 0,
  ]) {
    if (depth > 24) {
      return _unknown;
    }
    final evaluator = _Evaluator(project, scope, tokens, start, end, depth);
    try {
      final value = evaluator._expression();
      return evaluator.pos < end ? _unknown : value;
    } on Object {
      return _unknown;
    }
  }

  bool get _done => pos >= end;

  _Token? get _peek => _done ? null : tokens[pos];

  Object? _expression() {
    final condition = _binary(0);
    if (_peek?.isPunct('?') ?? false) {
      pos++;
      final whenTrue = _expression();
      if (!(_peek?.isPunct(':') ?? false)) {
        return _unknown;
      }
      pos++;
      final whenFalse = _expression();
      if (condition is bool) {
        return condition ? whenTrue : whenFalse;
      }
      return _unknown;
    }
    return condition;
  }

  static const List<List<String>> _levels = [
    ['||', '??'],
    ['&&'],
    ['===', '!==', '==', '!='],
    ['+', '-'],
    ['*', '/', '%'],
  ];

  String? _operator() {
    final token = _peek;
    if (token == null || token.kind != _Kind.punctuation) {
      return null;
    }
    if (token.text == '|' && pos + 1 < end && tokens[pos + 1].isPunct('|')) {
      return '||';
    }
    if (token.text == '&' && pos + 1 < end && tokens[pos + 1].isPunct('&')) {
      return '&&';
    }
    if (token.text == '?' && pos + 1 < end && tokens[pos + 1].isPunct('?')) {
      return '??';
    }
    if (token.text == '??' ||
        const {'===', '!==', '==', '!='}.contains(token.text)) {
      return token.text;
    }
    if (const {'+', '-', '*', '/', '%'}.contains(token.text)) {
      // `+=` and the like are never part of an expression we read.
      return token.text;
    }
    return null;
  }

  Object? _binary(int level) {
    if (level >= _levels.length) {
      return _unary();
    }
    var left = _binary(level + 1);
    while (true) {
      final operator = _operator();
      if (operator == null || !_levels[level].contains(operator)) {
        return left;
      }
      pos += (operator == '||' || operator == '&&')
          ? 2
          : (operator == '??' && !tokens[pos].isPunct('??') ? 2 : 1);
      final right = _binary(level + 1);
      left = _apply(operator, left, right);
    }
  }

  Object? _apply(String operator, Object? left, Object? right) {
    if (left is _Unknown || right is _Unknown) {
      if (operator == '+') {
        return _concatenate(left, right);
      }
      return _unknown;
    }
    switch (operator) {
      case '+':
        if (left is num && right is num) {
          return left + right;
        }
        return _concatenate(left, right);
      case '-' when left is num && right is num:
        return left - right;
      case '*' when left is num && right is num:
        return left * right;
      case '/' when left is num && right is num:
        return left / right;
      case '%' when left is num && right is num:
        return left % right;
      case '===' || '==':
        return _same(left, right);
      case '!==' || '!=':
        final same = _same(left, right);
        return same is bool ? !same : same;
      case '||':
        return _truthy(left) ? left : right;
      case '&&':
        return _truthy(left) ? right : left;
      case '??':
        return (left == null || left is _JsNull) ? right : left;
    }
    return _unknown;
  }

  static Object? _same(Object? left, Object? right) {
    bool comparable(Object? value) =>
        value == null ||
        value is _JsNull ||
        value is String ||
        value is num ||
        value is bool;
    if (!comparable(left) || !comparable(right)) {
      return _unknown;
    }
    if (left is num && right is num) {
      return left == right;
    }
    return left == right;
  }

  Object? _concatenate(Object? left, Object? right) {
    final parts = <Object>[..._partsOf(left), ..._partsOf(right)];
    if (parts.any((part) => part is Wildcard)) {
      return _Text(parts);
    }
    return parts.join();
  }

  static List<Object> _partsOf(Object? value) {
    if (value is _Text) {
      return value.parts;
    }
    if (value is _Unknown) {
      return const [Wildcard.instance];
    }
    if (value is String ||
        value is num ||
        value is bool ||
        value == null ||
        value is _JsNull) {
      return [jsString(value) ?? ''];
    }
    return const [Wildcard.instance];
  }

  static bool _truthy(Object? value) {
    if (value == null || value is _JsNull) {
      return false;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0 && !value.isNaN;
    }
    if (value is String) {
      return value.isNotEmpty;
    }
    return true;
  }

  Object? _unary() {
    final token = _peek;
    if (token != null && token.kind == _Kind.punctuation) {
      if (token.text == '-' || token.text == '+') {
        pos++;
        final value = _unary();
        if (value is num) {
          return token.text == '-' ? -value : value;
        }
        return _unknown;
      }
      if (token.text == '!') {
        pos++;
        final value = _unary();
        return value is _Unknown ? _unknown : !_truthy(value);
      }
    }
    if (token != null && token.isIdent('typeof')) {
      pos++;
      _unary();
      return _unknown;
    }
    if (token != null && token.isIdent('await')) {
      pos++;
      _unary();
      return _unknown;
    }
    return _postfix(_primary());
  }

  Object? _postfix(Object? initial) {
    var value = initial;
    var name = _lastIdentifier;
    while (!_done) {
      final token = tokens[pos];
      if (token.isPunct('.') || token.isPunct('?.')) {
        pos++;
        if (_done) {
          return _unknown;
        }
        if (tokens[pos].isPunct('(')) {
          // `?.(` optional call
          continue;
        }
        final member = tokens[pos++];
        if (member.kind != _Kind.identifier) {
          return _unknown;
        }
        if (!_done && tokens[pos].isPunct('(')) {
          final close = tokens[pos].match;
          final arguments = _arguments(pos + 1, close);
          pos = close + 1;
          value = _callMethod(value, name, member.text, arguments);
          name = null;
        } else {
          value = _member(value, member.text);
          name = null;
        }
      } else if (token.isPunct('[')) {
        final close = token.match;
        final index = evaluate(
          project,
          scope,
          tokens,
          pos + 1,
          close,
          depth + 1,
        );
        pos = close + 1;
        value = _index(value, index);
        name = null;
      } else if (token.isPunct('(')) {
        final close = token.match;
        final arguments = _arguments(pos + 1, close);
        pos = close + 1;
        value = _callFunction(name, arguments);
        name = null;
      } else if (token.isPunct('!') &&
          !(pos + 1 < end && tokens[pos + 1].isPunct('='))) {
        pos++;
      } else if (token.isIdent('as') || token.isIdent('satisfies')) {
        pos++;
        _skipType();
      } else {
        break;
      }
    }
    return value;
  }

  String? _lastIdentifier;

  /// Skips a type annotation: up to a delimiter at depth 0.
  void _skipType() {
    while (!_done) {
      final token = tokens[pos];
      if (token.isPunct(',') ||
          token.isPunct(')') ||
          token.isPunct(']') ||
          token.isPunct('}') ||
          token.isPunct(';') ||
          token.isPunct('?') ||
          token.isPunct(':') ||
          token.isPunct('=')) {
        return;
      }
      if (token.isIdent('as') || token.isIdent('satisfies')) {
        pos++;
        continue;
      }
      if ((token.isPunct('(') || token.isPunct('[') || token.isPunct('{')) &&
          token.match > pos) {
        pos = token.match;
      } else if (token.isPunct('<')) {
        pos = _skipAngles(tokens, pos) - 1;
      }
      pos++;
    }
  }

  List<Object?> _arguments(int start, int close) {
    final values = <Object?>[];
    var cursor = start;
    while (cursor < close) {
      final stop = _argumentEnd(tokens, cursor, close);
      values.add(evaluate(project, scope, tokens, cursor, stop, depth + 1));
      cursor = stop + 1;
    }
    return values;
  }

  Object? _primary() {
    _lastIdentifier = null;
    final token = _peek;
    if (token == null) {
      throw const FormatException('end');
    }
    switch (token.kind) {
      case _Kind.number:
        pos++;
        return _number(token.text);
      case _Kind.string:
        pos++;
        return token.value;
      case _Kind.template:
        pos++;
        return _template(token);
      case _Kind.regex:
        pos++;
        return _unknown;
      case _Kind.punctuation:
        return _primaryPunctuation(token);
      case _Kind.identifier:
        return _primaryIdentifier(token);
    }
  }

  Object? _primaryPunctuation(_Token token) {
    if (token.isPunct('[')) {
      final close = token.match;
      final value = _arrayLiteral(pos + 1, close);
      pos = close + 1;
      return value;
    }
    if (token.isPunct('{')) {
      final close = token.match;
      final value = _objectLiteral(pos + 1, close);
      pos = close + 1;
      return value;
    }
    if (token.isPunct('(')) {
      final close = token.match;
      // An arrow function: `(a, b) => ...` or `(a): T => ...`.
      var after = close + 1;
      if (after < end && tokens[after].isPunct(':')) {
        while (after < end && !tokens[after].isPunct('=>')) {
          after++;
        }
      }
      if (after < end && tokens[after].isPunct('=>')) {
        _skipArrowBody(after + 1);
        return _unknown;
      }
      pos++;
      final value = _expression();
      if (!(_peek?.isPunct(')') ?? false)) {
        throw const FormatException(')');
      }
      pos++;
      return value;
    }
    if (token.isPunct('<')) {
      // A type assertion `<T>value`.
      pos = _skipAngles(tokens, pos);
      return _unary();
    }
    throw FormatException('unexpected ${token.text}');
  }

  void _skipArrowBody(int start) {
    pos = start;
    if (!_done && tokens[pos].isPunct('{')) {
      pos = tokens[pos].match + 1;
      return;
    }
    _skipExpression();
  }

  /// Advances to the end of an expression: a delimiter at depth 0.
  void _skipExpression() {
    while (!_done) {
      final token = tokens[pos];
      if (token.isPunct(',') ||
          token.isPunct(')') ||
          token.isPunct(']') ||
          token.isPunct('}') ||
          token.isPunct(';')) {
        return;
      }
      if ((token.isPunct('(') || token.isPunct('[') || token.isPunct('{')) &&
          token.match > pos) {
        pos = token.match;
      }
      pos++;
    }
  }

  Object? _primaryIdentifier(_Token token) {
    final name = token.text;
    switch (name) {
      case 'true':
        pos++;
        return true;
      case 'false':
        pos++;
        return false;
      case 'null':
        pos++;
        return _jsNull;
      case 'undefined':
        pos++;
        return null;
      case 'NaN':
        pos++;
        return double.nan;
      case 'Infinity':
        pos++;
        return double.infinity;
      case 'new':
      case 'function':
      case 'async':
      case 'class':
        _skipExpression();
        return _unknown;
    }
    // `x => ...`
    if (pos + 1 < end && tokens[pos + 1].isPunct('=>')) {
      _skipArrowBody(pos + 2);
      return _unknown;
    }
    pos++;
    _lastIdentifier = name;
    // Names that are followed by `.` or `(` are handled by the postfix step,
    // which needs the name of the callee.
    if (!_done &&
        (tokens[pos].isPunct('.') ||
            tokens[pos].isPunct('(') ||
            tokens[pos].isPunct('?.'))) {
      final known = _lookup(name);
      if (known is _Unknown && _isGlobalNamespace(name)) {
        return _Namespace(name);
      }
      return known;
    }
    return _lookup(name);
  }

  static bool _isGlobalNamespace(String name) => const {
    'Object',
    'Number',
    'String',
    'Array',
    'Math',
    'JSON',
  }.contains(name);

  Object? _lookup(String name) {
    _Scope? s = scope;
    while (s != null) {
      if (s.values.containsKey(name)) {
        return s.values[name];
      }
      if (s.declarations.containsKey(name)) {
        return s._cache.putIfAbsent(name, () {
          final declaration = s!.declarations[name]!;
          return evaluate(
            project,
            s,
            s.file.tokens,
            declaration.start,
            declaration.end,
            depth + 1,
          );
        });
      }
      if (s.parent == null) {
        // File level.
        final fileConstant = s.file.constants[name];
        if (fileConstant != null) {
          return s._cache.putIfAbsent(name, () {
            return evaluate(
              project,
              s!,
              s.file.tokens,
              fileConstant.start,
              fileConstant.end,
              depth + 1,
            );
          });
        }
        final imported = s.file.imports[name];
        if (imported != null) {
          return _importedConstant(imported);
        }
      }
      s = s.parent;
    }
    return _unknown;
  }

  Object? _importedConstant(_ImportRef reference) {
    final file = project.file(reference.path);
    if (file == null) {
      return _unknown;
    }
    final declaration = file.constants[reference.exportedName];
    if (declaration == null) {
      return _unknown;
    }
    return evaluate(
      project,
      _Scope(file: file, parent: null),
      file.tokens,
      declaration.start,
      declaration.end,
      depth + 1,
    );
  }

  static num _number(String text) {
    final clean = text.replaceAll('_', '').replaceAll(RegExp(r'n$'), '');
    if (clean.startsWith('0x') || clean.startsWith('0X')) {
      return int.parse(clean.substring(2), radix: 16);
    }
    if (clean.startsWith('0b') || clean.startsWith('0B')) {
      return int.parse(clean.substring(2), radix: 2);
    }
    if (clean.startsWith('0o') || clean.startsWith('0O')) {
      return int.parse(clean.substring(2), radix: 8);
    }
    final parsed = num.parse(clean);
    if (parsed is double &&
        parsed == parsed.truncateToDouble() &&
        parsed.abs() < 9e15) {
      return parsed.toInt();
    }
    return parsed;
  }

  Object? _template(_Token token) {
    final parts = <Object>[];
    for (final part in token.parts!) {
      if (part is String) {
        parts.add(part);
      } else if (part is List<_Token>) {
        final value = evaluate(project, scope, part, 0, part.length, depth + 1);
        parts.addAll(_partsOf(value));
      }
    }
    final merged = <Object>[];
    for (final part in parts) {
      if (part is String && merged.isNotEmpty && merged.last is String) {
        merged.last = '${merged.last}$part';
      } else {
        merged.add(part);
      }
    }
    if (merged.any((part) => part is Wildcard)) {
      return _Text(merged);
    }
    return merged.join();
  }

  Object? _arrayLiteral(int start, int close) {
    final items = <Object?>[];
    var cursor = start;
    while (cursor < close) {
      final stop = _argumentEnd(tokens, cursor, close);
      if (stop > cursor) {
        if (tokens[cursor].isPunct('...')) {
          final spread = evaluate(
            project,
            scope,
            tokens,
            cursor + 1,
            stop,
            depth + 1,
          );
          if (spread is List<Object?>) {
            items.addAll(spread);
          } else if (spread is Set<Object?>) {
            items.addAll(spread);
          } else {
            return _unknown;
          }
        } else {
          items.add(evaluate(project, scope, tokens, cursor, stop, depth + 1));
        }
      }
      cursor = stop + 1;
    }
    return items;
  }

  Object? _objectLiteral(int start, int close) {
    final map = <String, Object?>{};
    var cursor = start;
    while (cursor < close) {
      final stop = _argumentEnd(tokens, cursor, close);
      if (stop > cursor) {
        final first = tokens[cursor];
        if (first.isPunct('...')) {
          final spread = evaluate(
            project,
            scope,
            tokens,
            cursor + 1,
            stop,
            depth + 1,
          );
          if (spread is Map<String, Object?>) {
            map.addAll(spread);
          } else {
            return _unknown;
          }
        } else if ((first.kind == _Kind.identifier ||
                first.kind == _Kind.string ||
                first.kind == _Kind.number) &&
            cursor + 1 < stop &&
            tokens[cursor + 1].isPunct(':')) {
          final key = first.kind == _Kind.string ? first.value! : first.text;
          map[key] = evaluate(
            project,
            scope,
            tokens,
            cursor + 2,
            stop,
            depth + 1,
          );
        } else if (first.kind == _Kind.identifier && cursor + 1 == stop) {
          map[first.text] = _lookup(first.text);
        } else {
          return _unknown;
        }
      }
      cursor = stop + 1;
    }
    return map;
  }

  Object? _member(Object? value, String name) {
    if (value is _Namespace) {
      return switch ((value.name, name)) {
        ('Number', 'NaN') => double.nan,
        ('Number', 'POSITIVE_INFINITY') => double.infinity,
        ('Number', 'NEGATIVE_INFINITY') => double.negativeInfinity,
        ('Number', 'MAX_SAFE_INTEGER') => 9007199254740991,
        ('Number', 'MIN_SAFE_INTEGER') => -9007199254740991,
        ('Number', 'MAX_VALUE') => double.maxFinite,
        ('Number', 'EPSILON') => 2.220446049250313e-16,
        _ => _unknown,
      };
    }
    if (value is Map<String, Object?>) {
      return value.containsKey(name) ? value[name] : null;
    }
    if (value is List<Object?> && name == 'length') {
      return value.length;
    }
    if (value is String && name == 'length') {
      return value.length;
    }
    return _unknown;
  }

  Object? _index(Object? value, Object? index) {
    if (value is List<Object?> && index is int) {
      return index >= 0 && index < value.length ? value[index] : null;
    }
    if (value is Map<String, Object?> && index is String) {
      return value[index];
    }
    return _unknown;
  }

  Object? _callFunction(String? name, List<Object?> arguments) {
    if (name == null) {
      return _unknown;
    }
    if (name == 'valuesOf' && arguments.length == 1) {
      return _callMethod(
        const _Namespace('Object'),
        'Object',
        'values',
        arguments,
      );
    }
    // A function of the project whose body is one `return`: the error and
    // builder functions the tables use. Its parameters are bound to the
    // arguments.
    var owner = scope.file;
    var function = owner.functions[name];
    if (function == null) {
      final reference = owner.imports[name];
      final file = reference == null ? null : project.file(reference.path);
      function = file?.functions[reference!.exportedName];
      if (file != null) {
        owner = file;
      }
    }
    if (function == null || depth > 12) {
      return _unknown;
    }
    final body = owner.tokens;
    if (function.bodyStart >= function.bodyEnd ||
        !body[function.bodyStart].isIdent('return')) {
      return _unknown;
    }
    var stop = function.bodyEnd;
    if (body[stop - 1].isPunct(';')) {
      stop--;
    }
    final inner = _Scope(file: owner, parent: null);
    for (var i = 0; i < function.parameters.length; i++) {
      inner.values[function.parameters[i]] = i < arguments.length
          ? arguments[i]
          : null;
    }
    return evaluate(
      project,
      inner,
      body,
      function.bodyStart + 1,
      stop,
      depth + 1,
    );
  }

  Object? _callMethod(
    Object? receiver,
    String? receiverName,
    String method,
    List<Object?> arguments,
  ) {
    if (receiver is _Namespace) {
      final argument = arguments.isEmpty ? null : arguments.first;
      switch ((receiver.name, method)) {
        case ('Object', 'values'):
          if (argument is Map<String, Object?>) {
            return argument.values.toList();
          }
          if (argument is List<Object?>) {
            return argument.toList();
          }
        case ('Object', 'keys'):
          if (argument is Map<String, Object?>) {
            return argument.keys.toList();
          }
        case ('Object', 'entries'):
          if (argument is Map<String, Object?>) {
            return [
              for (final MapEntry(:key, :value) in argument.entries)
                [key, value],
            ];
          }
        case ('String', 'fromCharCode'):
          if (arguments.every((item) => item is int)) {
            return String.fromCharCodes(arguments.cast<int>());
          }
        case ('Array', 'from'):
          if (argument is List<Object?>) {
            return argument.toList();
          }
      }
      return _unknown;
    }
    if (receiver is String) {
      switch (method) {
        case 'repeat':
          if (arguments.isNotEmpty &&
              arguments.first is int &&
              (arguments.first! as int) >= 0) {
            return receiver * (arguments.first! as int);
          }
        case 'trim':
          return receiver.trim();
        case 'toUpperCase':
          return receiver.toUpperCase();
        case 'toLowerCase':
          return receiver.toLowerCase();
      }
      return _unknown;
    }
    if (receiver is List<Object?>) {
      switch (method) {
        case 'slice':
          if (arguments.every((item) => item is int)) {
            final from = arguments.isNotEmpty ? arguments[0]! as int : 0;
            final to = arguments.length > 1
                ? arguments[1]! as int
                : receiver.length;
            return receiver.sublist(
              from.clamp(0, receiver.length),
              to.clamp(0, receiver.length),
            );
          }
        case 'concat':
          final merged = receiver.toList();
          for (final item in arguments) {
            if (item is List<Object?>) {
              merged.addAll(item);
            } else {
              merged.add(item);
            }
          }
          return merged;
        case 'join':
          if (receiver.every((item) => item is String || item is num)) {
            final separator = arguments.isEmpty ? ',' : arguments.first;
            if (separator is String) {
              return receiver.map(jsString).join(separator);
            }
          }
      }
      return _unknown;
    }
    return _unknown;
  }
}

/// `Object`, `Number`, `String`, `Array`: the globals whose members are read.
class _Namespace {
  const new(this.name);

  final String name;
}

// ---------------------------------------------------------------------------
// Formatting, as jest-each does
// ---------------------------------------------------------------------------

/// `String(value)` for a primitive, or null for anything else.
String? jsString(Object? value) {
  if (value == null) {
    return 'undefined';
  }
  if (value is _JsNull) {
    return 'null';
  }
  if (value is String) {
    return value;
  }
  if (value is bool) {
    return '$value';
  }
  if (value is num) {
    return jsNumber(value);
  }
  return null;
}

/// A number as JavaScript prints it.
String jsNumber(num value) {
  if (value.isNaN) {
    return 'NaN';
  }
  if (value.isInfinite) {
    return value.isNegative ? '-Infinity' : 'Infinity';
  }
  if (value == value.truncateToDouble() && value.abs() < 1e21) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// `JSON.stringify(value)`, or null when the value has no known JSON form.
String? jsJson(Object? value) {
  if (value == null) {
    return 'undefined';
  }
  if (value is _JsNull) {
    return 'null';
  }
  if (value is String) {
    return _quote(value);
  }
  if (value is bool) {
    return '$value';
  }
  if (value is num) {
    return value.isNaN || value.isInfinite ? 'null' : jsNumber(value);
  }
  if (value is List<Object?>) {
    final items = [
      for (final item in value)
        if (item == null) 'null' else jsJson(item),
    ];
    return items.contains(null) ? null : '[${items.join(',')}]';
  }
  if (value is Map<String, Object?>) {
    final fields = <String>[];
    for (final MapEntry(:key, :value) in value.entries) {
      if (value == null) {
        continue;
      }
      final json = jsJson(value);
      if (json == null) {
        return null;
      }
      fields.add('${_quote(key)}:$json');
    }
    return '{${fields.join(',')}}';
  }
  return null;
}

/// pretty-format in the one-line mode jest-each uses for `%p`, or null.
String? jsPretty(Object? value) {
  if (value == null) {
    return 'undefined';
  }
  if (value is _JsNull) {
    return 'null';
  }
  if (value is String) {
    return _quote(value);
  }
  if (value is bool) {
    return '$value';
  }
  if (value is num) {
    return jsNumber(value);
  }
  if (value is List<Object?>) {
    final items = [for (final item in value) jsPretty(item)];
    return items.contains(null) ? null : '[${items.join(', ')}]';
  }
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    final fields = <String>[];
    for (final key in keys) {
      final pretty = jsPretty(value[key]);
      if (pretty == null) {
        return null;
      }
      fields.add('${_quote(key)}: $pretty');
    }
    return '{${fields.join(', ')}}';
  }
  return null;
}

/// A string as JSON writes it: lone surrogates as `\udxxx`.
String _quote(String text) {
  final out = StringBuffer('"');
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    final high = unit >= 0xd800 && unit <= 0xdbff;
    final low = unit >= 0xdc00 && unit <= 0xdfff;
    if (high &&
        index + 1 < text.length &&
        text.codeUnitAt(index + 1) >= 0xdc00 &&
        text.codeUnitAt(index + 1) <= 0xdfff) {
      out
        ..writeCharCode(unit)
        ..writeCharCode(text.codeUnitAt(index + 1));
      index++;
    } else if (high || low) {
      out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    } else {
      out.write(switch (unit) {
        0x22 => r'\"',
        0x5c => r'\\',
        0x08 => r'\b',
        0x0c => r'\f',
        0x0a => r'\n',
        0x0d => r'\r',
        0x09 => r'\t',
        < 0x20 => '\\u${unit.toRadixString(16).padLeft(4, '0')}',
        _ => String.fromCharCode(unit),
      });
    }
  }
  return (out..write('"')).toString();
}

/// Replaces the placeholders of a jest-each [title] with the [row] values, in
/// order. A value that cannot be printed becomes a [Wildcard].
List<Object> formatEachTitle(Object title, List<Object?> row, int index) {
  var parts = <Object>[if (title is _Text) ...title.parts else title];
  // The row index first: `%#`.
  parts = [
    for (final part in parts)
      if (part is String)
        ..._split(
          part.replaceAll('%%', '\u0000').replaceAll('%#', '$index'),
          const [],
        )
      else
        part,
  ];
  for (final value in row) {
    var replaced = false;
    final next = <Object>[];
    for (final part in parts) {
      if (replaced || part is! String) {
        next.add(part);
        continue;
      }
      final match = RegExp('%[sdifjop]').firstMatch(part);
      if (match == null) {
        next.add(part);
        continue;
      }
      replaced = true;
      final text = _formatPlaceholder(match.group(0)!, value);
      next
        ..add(part.substring(0, match.start))
        ..add(text ?? Wildcard.instance)
        ..add(part.substring(match.end));
    }
    parts = next;
  }
  return _merge([
    for (final part in parts)
      if (part is String) part.replaceAll('\u0000', '%') else part,
  ]);
}

List<Object> _split(String text, List<Object> _) => [text];

List<Object> _merge(List<Object> parts) {
  final merged = <Object>[];
  for (final part in parts) {
    if (part is String && part.isEmpty) {
      continue;
    }
    if (part is String && merged.isNotEmpty && merged.last is String) {
      merged.last = '${merged.last}$part';
    } else if (part is Wildcard &&
        merged.isNotEmpty &&
        merged.last is Wildcard) {
      continue;
    } else {
      merged.add(part);
    }
  }
  return merged;
}

String? _formatPlaceholder(String placeholder, Object? value) {
  if (value is _Unknown) {
    return null;
  }
  switch (placeholder) {
    case '%s':
      return jsString(value);
    case '%p':
      return jsPretty(value);
    case '%j':
      return jsJson(value);
    case '%d':
    case '%i':
    case '%f':
      if (value is num) {
        return placeholder == '%i'
            ? jsNumber(value.truncate())
            : jsNumber(value);
      }
      return null;
  }
  return null;
}

// ---------------------------------------------------------------------------
// The scan
// ---------------------------------------------------------------------------

const Set<String> _suiteNames = {'describe', 'xdescribe', 'fdescribe'};
const Set<String> _testNames = {'it', 'test', 'xit', 'xtest', 'fit', 'ftest'};
const Set<String> _modifiers = {
  'skip',
  'only',
  'todo',
  'concurrent',
  'failing',
  'each',
  'sequential',
};
const int _maxContractDepth = 8;

class _Scanner {
  new(this.project);

  final _Project project;

  /// Finds the tests in `file.tokens[start, end)` and appends them to [out].
  void scanRange(
    _SourceFile file,
    int start,
    int end,
    _Scope scope,
    List<List<Object>> ancestors,
    List<TsTest> out,
    int depth, {
    bool skipped = false,
  }) {
    final tokens = file.tokens;
    _collectDeclarations(tokens, start, end, scope);
    var index = start;
    while (index < end) {
      final token = tokens[index];
      final call = _readCall(tokens, index, end);
      if (call != null) {
        _handleCall(file, call, scope, ancestors, out, depth, skipped);
        index = call.end;
        continue;
      }
      if (token.kind == _Kind.identifier &&
          index + 1 < end &&
          tokens[index + 1].isPunct('(') &&
          _atStatementStart(tokens, index, start) &&
          depth < _maxContractDepth) {
        final expanded = _expandContract(
          file,
          token.text,
          index,
          scope,
          ancestors,
          out,
          depth,
          skipped,
        );
        if (expanded) {
          index = tokens[index + 1].match + 1;
          continue;
        }
      }
      index++;
    }
  }

  void _collectDeclarations(
    List<_Token> tokens,
    int start,
    int end,
    _Scope scope,
  ) {
    var index = start;
    while (index < end) {
      final token = tokens[index];
      if ((token.isIdent('const') || token.isIdent('let')) &&
          index + 1 < end &&
          tokens[index + 1].kind == _Kind.identifier &&
          _atStatementStart(tokens, index, start)) {
        final name = tokens[index + 1].text;
        final stop = _statementEnd(tokens, index + 2, end);
        final equals = _findAssignment(tokens, index + 2, stop);
        if (equals != null) {
          scope.declarations[name] = _Declaration(equals + 1, stop);
        }
        index = stop;
        continue;
      }
      if ((token.isPunct('{') || token.isPunct('(') || token.isPunct('[')) &&
          token.match > index) {
        index = token.match + 1;
        continue;
      }
      index++;
    }
  }

  bool _atStatementStart(List<_Token> tokens, int index, int start) {
    if (index == start) {
      return true;
    }
    final previous = tokens[index - 1];
    return previous.isPunct(';') ||
        previous.isPunct('{') ||
        previous.isPunct('}');
  }

  /// The call of `describe` / `it` / `test` (or of a `.each` table) at [index].
  _TestCall? _readCall(List<_Token> tokens, int index, int end) {
    final token = tokens[index];
    var cursor = index;
    String? name;
    if (token.isPunct('(') &&
        token.match > index &&
        token.match + 1 < end &&
        tokens[token.match + 1].isPunct('(')) {
      // `(cond ? describe : describe.skip)(title, body)`
      for (var inner = index + 1; inner < token.match; inner++) {
        final candidate = tokens[inner];
        if (candidate.kind == _Kind.identifier &&
            (_suiteNames.contains(candidate.text) ||
                _testNames.contains(candidate.text)) &&
            !(inner > 0 && tokens[inner - 1].isPunct('.'))) {
          name = candidate.text;
          break;
        }
      }
      if (name == null) {
        return null;
      }
      cursor = token.match + 1;
      return _finishCall(
        tokens,
        name,
        cursor,
        end,
        isSkip: false,
        each: false,
        start: index,
      );
    }
    if (token.kind != _Kind.identifier ||
        !(_suiteNames.contains(token.text) ||
            _testNames.contains(token.text))) {
      return null;
    }
    if (index > 0 &&
        (tokens[index - 1].isPunct('.') ||
            tokens[index - 1].isIdent('function'))) {
      return null;
    }
    name = token.text;
    cursor = index + 1;
    var each = false;
    var skip = name.startsWith('x');
    var todo = false;
    while (cursor + 1 < end &&
        tokens[cursor].isPunct('.') &&
        tokens[cursor + 1].kind == _Kind.identifier &&
        _modifiers.contains(tokens[cursor + 1].text)) {
      final modifier = tokens[cursor + 1].text;
      each = each || modifier == 'each';
      skip = skip || modifier == 'skip';
      todo = todo || modifier == 'todo';
      cursor += 2;
    }
    if (cursor >= end) {
      return null;
    }
    int? tableStart;
    int? tableEnd;
    if (each) {
      if (tokens[cursor].isPunct('<')) {
        cursor = _skipAngles(tokens, cursor);
      }
      if (cursor >= end || !tokens[cursor].isPunct('(')) {
        return null;
      }
      tableStart = cursor + 1;
      tableEnd = tokens[cursor].match;
      cursor = tableEnd + 1;
    }
    return _finishCall(
      tokens,
      name,
      cursor,
      end,
      isSkip: skip || todo,
      each: each,
      start: index,
      tableStart: tableStart,
      tableEnd: tableEnd,
    );
  }

  _TestCall? _finishCall(
    List<_Token> tokens,
    String name,
    int cursor,
    int end, {
    required bool isSkip,
    required bool each,
    required int start,
    int? tableStart,
    int? tableEnd,
  }) {
    if (cursor >= end || !tokens[cursor].isPunct('(')) {
      return null;
    }
    final close = tokens[cursor].match;
    if (close < 0) {
      return null;
    }
    return _TestCall(
      isSuite: _suiteNames.contains(name),
      skipped: isSkip,
      each: each,
      argumentsStart: cursor + 1,
      argumentsEnd: close,
      end: close + 1,
      tableStart: tableStart,
      tableEnd: tableEnd,
      start: start,
    );
  }

  void _handleCall(
    _SourceFile file,
    _TestCall call,
    _Scope scope,
    List<List<Object>> ancestors,
    List<TsTest> out,
    int depth,
    bool inheritedSkip,
  ) {
    final tokens = file.tokens;
    final firstEnd = _argumentEnd(
      tokens,
      call.argumentsStart,
      call.argumentsEnd,
    );
    final title = _Evaluator.evaluate(
      project,
      scope,
      tokens,
      call.argumentsStart,
      firstEnd,
    );
    final skipped = inheritedSkip || call.skipped;
    final bodyStart = firstEnd + 1;

    // The rows of the table: one expansion per row. An unknown table is one
    // expansion with unknown values.
    final rows = <List<Object?>?>[];
    if (call.each) {
      final table = _Evaluator.evaluate(
        project,
        scope,
        tokens,
        call.tableStart!,
        call.tableEnd!,
      );
      if (table is List<Object?>) {
        final allRows =
            table.isNotEmpty && table.every((row) => row is List<Object?>);
        for (final row in table) {
          rows.add(allRows ? List<Object?>.from(row! as List<Object?>) : [row]);
        }
      } else {
        rows.add(null);
      }
    } else {
      rows.add(const []);
    }

    final parameters = call.isSuite
        ? _callbackParameters(tokens, bodyStart, call.argumentsEnd)
        : const <String>[];
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final List<Object> name;
      if (!call.each) {
        name = _titleParts(title);
      } else if (row == null) {
        name = _merge([..._titleWithoutPlaceholders(title), Wildcard.instance]);
      } else {
        name = formatEachTitle(_asTitle(title), row, rowIndex);
      }
      if (call.isSuite) {
        final range = _callbackBody(tokens, bodyStart, call.argumentsEnd);
        if (range == null) {
          continue;
        }
        final inner = _Scope(file: file, parent: scope);
        for (var i = 0; i < parameters.length; i++) {
          if (parameters[i] != '_') {
            inner.values[parameters[i]] = row == null
                ? _unknown
                : (i < row.length ? row[i] : null);
          }
        }
        scanRange(
          file,
          range.$1,
          range.$2,
          inner,
          [...ancestors, name],
          out,
          depth,
          skipped: skipped,
        );
      } else {
        out.add(
          TsTest(
            _merge([
              for (final ancestor in ancestors) ...[...ancestor, ' '],
              ...name,
            ]),
            skipped: skipped,
          ),
        );
      }
    }
  }

  Object _asTitle(Object? title) => title is String || title is _Text
      ? title!
      : _Text(const [Wildcard.instance]);

  List<Object> _titleParts(Object? title) {
    if (title is String) {
      return [title];
    }
    if (title is _Text) {
      return title.parts;
    }
    return const [Wildcard.instance];
  }

  /// The title of an unknown table, with each placeholder as a wildcard.
  List<Object> _titleWithoutPlaceholders(Object? title) {
    final parts = _titleParts(title);
    return [
      for (final part in parts)
        if (part is String) ..._wildcardPlaceholders(part) else part,
    ];
  }

  List<Object> _wildcardPlaceholders(String text) {
    final out = <Object>[];
    var last = 0;
    for (final match in RegExp('%[sdifjop#]').allMatches(text)) {
      out
        ..add(text.substring(last, match.start))
        ..add(Wildcard.instance);
      last = match.end;
    }
    out.add(text.substring(last));
    return _merge(out.where((part) => part != '').toList());
  }

  /// The parameter names of the callback that starts at [start].
  List<String> _callbackParameters(List<_Token> tokens, int start, int end) {
    var cursor = start;
    while (cursor < end) {
      final token = tokens[cursor];
      if (token.isPunct('(') && token.match > cursor) {
        final after = token.match + 1;
        if (after < end &&
            (tokens[after].isPunct('=>') || tokens[after].isPunct(':'))) {
          return _parameterNames(tokens, cursor + 1, token.match);
        }
        cursor = token.match + 1;
        continue;
      }
      if (token.kind == _Kind.identifier &&
          cursor + 1 < end &&
          tokens[cursor + 1].isPunct('=>')) {
        return [token.text];
      }
      if (token.isIdent('function')) {
        final declaration = _readFunction(tokens, cursor);
        if (declaration != null) {
          return declaration.$2.parameters;
        }
      }
      cursor++;
    }
    return const [];
  }

  /// The range of the statements of the callback that starts at [start].
  (int, int)? _callbackBody(List<_Token> tokens, int start, int end) {
    var cursor = start;
    while (cursor < end) {
      final token = tokens[cursor];
      if (token.isPunct('=>')) {
        return cursor + 1 < end && tokens[cursor + 1].isPunct('{')
            ? (cursor + 2, tokens[cursor + 1].match)
            : null;
      }
      if (token.isIdent('function')) {
        var inner = cursor;
        while (inner < end && !tokens[inner].isPunct('{')) {
          if (tokens[inner].isPunct('(') && tokens[inner].match > inner) {
            inner = tokens[inner].match;
          }
          inner++;
        }
        return inner < end ? (inner + 1, tokens[inner].match) : null;
      }
      if ((token.isPunct('(') || token.isPunct('[') || token.isPunct('{')) &&
          token.match > cursor) {
        cursor = token.match;
      }
      cursor++;
    }
    return null;
  }

  /// Expands the call of a function that declares tests (a contract suite).
  bool _expandContract(
    _SourceFile file,
    String name,
    int index,
    _Scope scope,
    List<List<Object>> ancestors,
    List<TsTest> out,
    int depth,
    bool skipped,
  ) {
    final local = file.functions[name];
    final reference = file.imports[name];
    final owner = local != null
        ? file
        : (reference == null ? null : project.file(reference.path));
    final declaration =
        local ??
        (reference == null ? null : owner?.functions[reference.exportedName]);
    if (owner == null ||
        declaration == null ||
        !_declaresTests(owner.tokens, declaration)) {
      return false;
    }
    final tokens = file.tokens;
    final open = index + 1;
    final close = tokens[open].match;
    final inner = _Scope(
      file: owner,
      parent: _Scope(file: owner, parent: null),
    );
    var cursor = open + 1;
    var parameter = 0;
    while (cursor < close && parameter < declaration.parameters.length) {
      final stop = _argumentEnd(tokens, cursor, close);
      if (declaration.parameters[parameter] != '_') {
        inner.values[declaration.parameters[parameter]] = _Evaluator.evaluate(
          project,
          scope,
          tokens,
          cursor,
          stop,
        );
      }
      parameter++;
      cursor = stop + 1;
    }
    scanRange(
      owner,
      declaration.bodyStart,
      declaration.bodyEnd,
      inner,
      ancestors,
      out,
      depth + 1,
      skipped: skipped,
    );
    return true;
  }

  bool _declaresTests(List<_Token> tokens, _FunctionDeclaration declaration) {
    for (
      var index = declaration.bodyStart;
      index < declaration.bodyEnd;
      index++
    ) {
      final token = tokens[index];
      if (token.kind == _Kind.identifier &&
          (_suiteNames.contains(token.text) ||
              _testNames.contains(token.text)) &&
          index + 1 < declaration.bodyEnd &&
          (tokens[index + 1].isPunct('(') || tokens[index + 1].isPunct('.'))) {
        return true;
      }
    }
    return false;
  }
}

class _TestCall {
  const new({
    required this.isSuite,
    required this.skipped,
    required this.each,
    required this.argumentsStart,
    required this.argumentsEnd,
    required this.end,
    required this.start,
    this.tableStart,
    this.tableEnd,
  });

  final bool isSuite;
  final bool skipped;
  final bool each;
  final int argumentsStart;
  final int argumentsEnd;
  final int end;
  final int start;
  final int? tableStart;
  final int? tableEnd;
}
