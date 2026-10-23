import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/infrastructure/shared/issue_paths.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

// What the schemas of the API have in common: the way an instant is written,
// and how a body is read into its wire class.
//
// A wire class is the shape of a JSON body, read by the code json_serializable
// generates in `checked` mode. It checks that each field is there and has the
// type of the API, and ignores the fields it does not know. The values
// themselves are checked by the factories of the domain, in the mappers: a
// status that is not one, a blank title, a duplicate id.

/// The number of milliseconds in a day.
const int millisPerDay = 86400000;

const int _millisPerHour = 3600000;
const int _millisPerMinute = 60000;
const int _millisPerSecond = 1000;

/// The latest time value a date can hold, in milliseconds from the epoch,
/// either side of it.
const int _maxTimeValue = 8640000000000000;

/// ISO 8601 date and time with a zone, as `Date.prototype.toISOString` writes
/// it (a `Z`, and a year with a sign and six digits outside 0000-9999) or with
/// an offset: `2030-03-17T17:46:40.000Z`, `2030-03-17T18:46:40+01:00`.
final RegExp _iso8601Instant = RegExp(
  r'^(\d{4}|[+-]\d{6})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
  r'(?:\.(\d{1,9}))?(?:Z|([+-])(\d{2}):(\d{2}))$',
);

const String _notAnInstant = 'not an instant';

int _floorDiv(int dividend, int divisor) =>
    (dividend - dividend % divisor) ~/ divisor;

bool _isLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

int _daysInMonth(int year, int month) => switch (month) {
  2 => _isLeapYear(year) ? 29 : 28,
  4 || 6 || 9 || 11 => 30,
  _ => 31,
};

/// The number of days from 1970-01-01 to the given day of the proleptic
/// Gregorian calendar.
int _daysFromCivil(int year, int month, int day) {
  final shifted = month <= 2 ? year - 1 : year;
  final era = _floorDiv(shifted, 400);
  final yearOfEra = shifted - era * 400;
  final dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) ~/ 5 + day - 1;
  final dayOfEra =
      yearOfEra * 365 + yearOfEra ~/ 4 - yearOfEra ~/ 100 + dayOfYear;
  return era * 146097 + dayOfEra - 719468;
}

/// The day of the proleptic Gregorian calendar that is [days] days from
/// 1970-01-01.
(int year, int month, int day) _civilFromDays(int days) {
  final shifted = days + 719468;
  final era = _floorDiv(shifted, 146097);
  final dayOfEra = shifted - era * 146097;
  final yearOfEra =
      (dayOfEra - dayOfEra ~/ 1460 + dayOfEra ~/ 36524 - dayOfEra ~/ 146096) ~/
      365;
  final dayOfYear =
      dayOfEra - (365 * yearOfEra + yearOfEra ~/ 4 - yearOfEra ~/ 100);
  final monthIndex = (5 * dayOfYear + 2) ~/ 153;
  final day = dayOfYear - (153 * monthIndex + 2) ~/ 5 + 1;
  final month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9;
  return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day);
}

/// The milliseconds since the epoch an ISO 8601 text stands for, or `null` when
/// it is not a date: a month 13, a 32nd day, a 25th hour, a time beyond the
/// range of a date. The check is done here, on the numbers, because a library
/// parser rolls an impossible day over to the next month.
int? _parseIso8601(String text) {
  final match = _iso8601Instant.firstMatch(text);
  if (match == null) {
    return null;
  }
  final yearText = match.group(1)!;
  final year = int.parse(yearText);
  if (yearText == '-000000') {
    return null;
  }
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final fraction = match.group(7) ?? '';
  final millis = fraction.isEmpty
      ? 0
      : int.parse(fraction.padRight(3, '0').substring(0, 3));

  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > _daysInMonth(year, month) ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  // 24:00:00 is the end of a day, and nothing else may have the hour 24.
  if (hour > 24 ||
      (hour == 24 && (minute != 0 || second != 0 || millis != 0))) {
    return null;
  }

  var offsetMillis = 0;
  final offsetSign = match.group(8);
  if (offsetSign != null) {
    final offsetHours = int.parse(match.group(9)!);
    final offsetMinutes = int.parse(match.group(10)!);
    if (offsetHours > 23 || offsetMinutes > 59) {
      return null;
    }
    offsetMillis =
        (offsetHours * _millisPerHour + offsetMinutes * _millisPerMinute) *
        (offsetSign == '-' ? -1 : 1);
  }

  final instant =
      _daysFromCivil(year, month, day) * millisPerDay +
      hour * _millisPerHour +
      minute * _millisPerMinute +
      second * _millisPerSecond +
      millis -
      offsetMillis;
  return instant.abs() > _maxTimeValue ? null : instant;
}

/// An instant on the wire: an ISO 8601 string, read as a number of
/// milliseconds since the epoch. Throws a [FormatException] for anything else
/// (a number, a date with no time, an impossible day), which the generated code
/// reports as the flaw of that field.
int readInstantMillis(Object raw) {
  final millis = raw is String ? _parseIso8601(raw) : null;
  if (millis == null) {
    throw const FormatException(_notAnInstant);
  }
  return millis;
}

/// A number of milliseconds since the epoch as the API writes an instant,
/// `Date.prototype.toISOString` style: `2030-03-17T17:46:40.000Z`.
String writeInstantMillis(int epochMillis) {
  final days = _floorDiv(epochMillis, millisPerDay);
  final inDay = epochMillis - days * millisPerDay;
  final (year, month, day) = _civilFromDays(days);
  final yearText = year >= 0 && year <= 9999
      ? year.toString().padLeft(4, '0')
      : '${year < 0 ? '-' : '+'}${year.abs().toString().padLeft(6, '0')}';
  String two(int value) => value.toString().padLeft(2, '0');
  final hour = inDay ~/ _millisPerHour;
  final minute = inDay % _millisPerHour ~/ _millisPerMinute;
  final second = inDay % _millisPerMinute ~/ _millisPerSecond;
  final millis = inDay % _millisPerSecond;
  return '$yearText-${two(month)}-${two(day)}T${two(hour)}:${two(minute)}:'
      '${two(second)}.${millis.toString().padLeft(3, '0')}Z';
}

/// [writeInstantMillis] for an instant that may be absent.
String? writeOptionalInstantMillis(int? epochMillis) =>
    epochMillis == null ? null : writeInstantMillis(epochMillis);

/// An instant as the API writes it.
String toIsoString(Instant instant) => writeInstantMillis(instant);

/// Why a body did not have the shape of its schema: where, never what it held.
@immutable
final class WireFailure {
  /// Creates the failure of a body whose flaws are at [issuePaths].
  const new(this.issuePaths);

  /// The places where the body broke the schema, as `issuePathsOf` writes
  /// them.
  final String issuePaths;

  @override
  bool operator ==(Object other) =>
      other is WireFailure && other.issuePaths == issuePaths;

  @override
  int get hashCode => issuePaths.hashCode;

  @override
  String toString() => 'WireFailure($issuePaths)';
}

/// The path from [root] to the map [target] (field names and positions in the
/// lists), or `null` when [target] is not inside [root].
List<Object>? _pathTo(Object? root, Map<dynamic, dynamic> target) {
  if (identical(root, target)) {
    return const [];
  }
  if (root is Map<dynamic, dynamic>) {
    for (final entry in root.entries) {
      final below = _pathTo(entry.value, target);
      if (below != null) {
        return [entry.key as Object, ...below];
      }
    }
  } else if (root is List<dynamic>) {
    for (var index = 0; index < root.length; index++) {
      final below = _pathTo(root[index], target);
      if (below != null) {
        return [index, ...below];
      }
    }
  }
  return null;
}

/// Reads a decoded JSON body with the `fromJson` of a wire class, or says where
/// it broke its schema. A body that is not an object is a flaw of the body as a
/// whole. Nothing is thrown, and the failure holds the places of the flaw and
/// no value.
///
/// The generated code stops at the first flaw, so the failure names that one
/// place.
Result<T, WireFailure> decodeWire<T>(
  Object? json,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (json is! Map<String, dynamic>) {
    return err(const WireFailure(rootPath));
  }
  try {
    return ok(fromJson(json));
  } on CheckedFromJsonException catch (exception) {
    final parents = _pathTo(json, exception.map) ?? const <Object>[];
    final key = exception.key;
    return err(
      WireFailure(
        issuePathsOf([
          [...parents, ?key],
        ]),
      ),
    );
  } on Object {
    // A wire class is read in `checked` mode, which wraps every flaw. Anything
    // else is a flaw of the body as a whole.
    return err(const WireFailure(rootPath));
  }
}
