/// Text that cannot be written in an address: it holds a surrogate code unit
/// that has no partner, which UTF-8 has no bytes for.
final class IllFormedTextException implements Exception {
  /// Creates the exception. It carries no part of the text it is about: the
  /// text may be an identifier, and an exception ends up in logs.
  const new();

  /// What went wrong, without the text.
  String get message => 'text is not well formed';

  @override
  String toString() => message;
}

const int _firstHighSurrogate = 0xD800;
const int _lastHighSurrogate = 0xDBFF;
const int _firstLowSurrogate = 0xDC00;
const int _lastLowSurrogate = 0xDFFF;

bool _isHigh(int unit) =>
    unit >= _firstHighSurrogate && unit <= _lastHighSurrogate;

bool _isLow(int unit) =>
    unit >= _firstLowSurrogate && unit <= _lastLowSurrogate;

/// Whether [text] is well formed UTF-16: every surrogate is half of a pair.
bool isWellFormed(String text) {
  final units = text.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (_isHigh(unit)) {
      if (index + 1 >= units.length || !_isLow(units[index + 1])) {
        return false;
      }
      index += 1;
    } else if (_isLow(unit)) {
      return false;
    }
  }
  return true;
}

/// [text] itself, or an [IllFormedTextException] when it is not well formed.
///
/// `Uri.encodeComponent` writes a lone surrogate as U+FFFD where
/// `encodeURIComponent` throws; the adapters refuse such an identifier, a
/// cursor or a header value instead of sending something else than they were
/// given.
String requireWellFormed(String text) {
  if (!isWellFormed(text)) {
    throw const IllFormedTextException();
  }
  return text;
}

/// `encodeURIComponent`: the text with every character the URI standard
/// reserves percent-encoded, or an [IllFormedTextException] for text that is
/// not well formed.
String encodeUriComponent(String text) =>
    Uri.encodeComponent(requireWellFormed(text));
