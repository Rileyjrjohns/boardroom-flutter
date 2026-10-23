import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';

/// The units that JavaScript's `String.prototype.trim` removes: the white space
/// and line terminators of ECMAScript. Dart's own `trim` removes a slightly
/// different set (it removes U+0085, which JavaScript keeps), so the domain
/// trims by this list to behave the same on every platform.
const Set<int> _whitespaceUnits = {
  0x0009, // tab
  0x000a, // line feed
  0x000b, // vertical tab
  0x000c, // form feed
  0x000d, // carriage return
  0x0020, // space
  0x00a0, // no-break space
  0x1680, // ogham space mark
  0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, //
  0x2009, 0x200a, // en quad to hair space
  0x2028, // line separator
  0x2029, // paragraph separator
  0x202f, // narrow no-break space
  0x205f, // medium mathematical space
  0x3000, // ideographic space
  0xfeff, // zero width no-break space (byte order mark)
};

/// The text with its leading and trailing white space removed. Inner white
/// space is kept.
String trimText(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && _whitespaceUnits.contains(text.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _whitespaceUnits.contains(text.codeUnitAt(end - 1))) {
    end--;
  }
  return text.substring(start, end);
}

/// The text with its surrounding whitespace removed. It must not be blank nor
/// longer than [maxLength].
Result<String, ValidationError> requireText(
  ValidationField field,
  String raw,
  int maxLength,
) {
  final text = trimText(raw);
  if (text.isEmpty) {
    return err(validationError(field, ValidationRule.required));
  }
  if (text.length > maxLength) {
    return err(validationError(field, ValidationRule.tooLong));
  }
  return ok(text);
}

/// Like [requireText] for a text that may be missing. A missing or blank text
/// is no text: the result is null, not an error.
Result<String?, ValidationError> optionalText(
  ValidationField field,
  String? raw,
  int maxLength,
) {
  if (raw == null || trimText(raw).isEmpty) {
    return ok<String?>(null);
  }
  return requireText(field, raw, maxLength);
}

/// An integer between [min] and [max], both included. The value is a [num]
/// because it comes from outside (a decoded answer, a stored row) and may be a
/// fraction, `NaN` or infinite: those are `notAnInteger`.
Result<int, ValidationError> requireIntegerInRange(
  ValidationField field,
  num value,
  int min,
  int max,
) {
  final isInteger =
      value is int || (value.isFinite && value == value.truncateToDouble());
  if (!isInteger) {
    return err(validationError(field, ValidationRule.notAnInteger));
  }
  if (value < min || value > max) {
    return err(validationError(field, ValidationRule.outOfRange));
  }
  return ok(value.toInt());
}

const int _firstHighSurrogate = 0xd800;
const int _lastHighSurrogate = 0xdbff;
const int _firstLowSurrogate = 0xdc00;
const int _lastLowSurrogate = 0xdfff;

bool _isHighSurrogate(int unit) =>
    unit >= _firstHighSurrogate && unit <= _lastHighSurrogate;

bool _isLowSurrogate(int unit) =>
    unit >= _firstLowSurrogate && unit <= _lastLowSurrogate;

/// True when the text is well-formed UTF-16: every surrogate is half of a pair,
/// a high one followed by a low one. A text that is not cannot be encoded as
/// UTF-8 or percent-encoded, so it cannot be put in a URL, a header or a file
/// name.
bool isWellFormedText(String text) {
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    if (_isLowSurrogate(unit)) {
      return false;
    }
    if (!_isHighSurrogate(unit)) {
      continue;
    }
    index++;
    if (index >= text.length || !_isLowSurrogate(text.codeUnitAt(index))) {
      return false;
    }
  }
  return true;
}

/// True when two members share a key: used to check that the members of a
/// collection are unique.
bool hasDuplicates(Iterable<Object> keys) => keys.toSet().length != keys.length;
