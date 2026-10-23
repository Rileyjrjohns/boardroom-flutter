/// A member of a closed set of stable strings: an enumeration value or an error
/// code. The string is what is stored, sent to the server and mapped to a
/// translation key, so it is spelled exactly as in the specification and never
/// renamed. Every Dart enumeration of the domain implements it.
abstract interface class StableValue {
  /// The stable string of this member, for example `'networkUnavailable'`.
  String get value;
}

/// The stable strings of [constants], in order. For an enumeration,
/// `valuesOf(VoteChoice.values)` is `['for', 'against', 'abstain']`.
List<String> valuesOf(Iterable<StableValue> constants) => [
  for (final constant in constants) constant.value,
];

/// The member of [values] whose string equals [raw], or null. Searching the
/// list instead of parsing keeps the result typed.
T? findConstant<T extends StableValue>(Iterable<T> values, String raw) {
  for (final candidate in values) {
    if (candidate.value == raw) {
      return candidate;
    }
  }
  return null;
}
