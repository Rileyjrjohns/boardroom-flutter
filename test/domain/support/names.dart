import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/constants.dart';

// The names of the expanded tests. A Jest `it.each` title is a template where
// `%s`, `%j` and `%p` are replaced by the values of the row; a Dart loop builds
// the same title with these functions, so that the name of the test is
// identical to the React Native one (tool/scenario_parity.dart compares them).

/// A number as JavaScript prints it: `NaN`, `Infinity`, `-1`, `1.5`, and `0`
/// for a whole value.
String formatNumber(num value) {
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

/// `JSON.stringify` of a string: double quotes, the short escapes, `\u00xx`
/// for the other control characters, and `\udxxx` (lower case) for a surrogate
/// that is not half of a pair. Everything else is written as is.
String _quote(String text) {
  final out = StringBuffer('"');
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    final isHigh = unit >= 0xd800 && unit <= 0xdbff;
    final isLow = unit >= 0xdc00 && unit <= 0xdfff;
    if (isHigh &&
        index + 1 < text.length &&
        text.codeUnitAt(index + 1) >= 0xdc00 &&
        text.codeUnitAt(index + 1) <= 0xdfff) {
      out
        ..writeCharCode(unit)
        ..writeCharCode(text.codeUnitAt(index + 1));
      index++;
    } else if (isHigh || isLow) {
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

/// The `%j` of Jest: the value as `JSON.stringify` writes it. A `null` is the
/// `undefined` of the React Native test.
String formatJson(Object? value) => switch (value) {
  null => 'undefined',
  final String text => _quote(text),
  final num number => formatNumber(number),
  final bool flag => '$flag',
  _ => throw ArgumentError('Not supported by formatJson: $value'),
};

/// The `%p` of Jest: the value as pretty-format writes it on one line. Strings
/// are quoted, numbers are as JavaScript prints them, an object is written with
/// its keys in alphabetical order, and an [AppError] is the object it stands
/// for (its `code` and its [AppError.payload]).
String formatPretty(Object? value) => switch (value) {
  null => 'undefined',
  final String text => _quote(text),
  final num number => formatNumber(number),
  final bool flag => '$flag',
  final StableValue member => _quote(member.value),
  final AppError error => formatPretty({'code': error.code, ...error.payload}),
  final Map<String, Object?> map => _object(map),
  final Iterable<Object?> items => '[${items.map(formatPretty).join(', ')}]',
  _ => _quote('$value'),
};

String _object(Map<String, Object?> map) {
  final keys = map.keys.toList()..sort();
  final fields = [
    for (final key in keys) '${_quote(key)}: ${formatPretty(map[key])}',
  ];
  return '{${fields.join(', ')}}';
}
