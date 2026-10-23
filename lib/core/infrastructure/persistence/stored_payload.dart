import 'dart:convert';

import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:meta/meta.dart';

// What the caches share when a row is read back: the payload is JSON in the
// format of the cache, checked against its stored class and then through the
// factories of the domain, and a row that does not pass is a miss.

/// The cause a cache reports for a row it cannot read back. A kind of failure,
/// never a value of the row.
const String unreadableEntryCause = 'stored entry unreadable';

/// A stored payload that does not read back. When the flaw is in the shape of
/// the JSON, [issuePaths] says where; a text that is not JSON, or values the
/// domain refuses, have no place to report.
@immutable
final class Unreadable {
  /// Creates the failure of a payload whose flaws are at [issuePaths], if
  /// known.
  const new([this.issuePaths]);

  /// The places where the payload broke its stored class (`agenda.0.status`),
  /// never what it held.
  final String? issuePaths;

  @override
  bool operator ==(Object other) =>
      other is Unreadable && other.issuePaths == issuePaths;

  @override
  int get hashCode => issuePaths.hashCode;

  @override
  String toString() => 'Unreadable($issuePaths)';
}

/// A payload read back: it is JSON, it has the shape of the stored class
/// ([read] checks it), and its values pass the domain ([build]).
Result<T, Unreadable> decodePayload<S, T>(
  String payload,
  S Function(Map<String, dynamic> json) read,
  Result<T, Object?> Function(S stored) build,
) {
  final Object? json;
  try {
    json = jsonDecode(payload);
  } on FormatException {
    return err(const Unreadable());
  }
  switch (decodeWire(json, read)) {
    case Err(:final error):
      return err(Unreadable(error.issuePaths));
    case Ok(:final value):
      return switch (build(value)) {
        Ok(:final value) => ok(value),
        Err() => err(const Unreadable()),
      };
  }
}

/// The instant a column holds, or `null` when it is not one: not a number, not
/// a whole one, or out of the range of an instant.
Instant? instantOf(Object? column) {
  if (column is! num) {
    return null;
  }
  return switch (parseInstant(column)) {
    Ok(:final value) => value,
    Err() => null,
  };
}
