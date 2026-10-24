import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Dates, times and numbers as the user reads them, for their locale
/// (docs/spec/screens.md "How to read this file"). The domain holds an
/// `Instant` and no time zone; the zone is the one of the device, unless a
/// test gives one through `toLocal`.
final class Formatters {
  /// Creates the formatters of [locale] (`en`, `fr`, `fr_CA`).
  new(String locale, {DateTime Function(int epochMillis)? toLocal})
    : _toLocal = toLocal ?? _deviceTime,
      _compact = DateFormat.yMMMEd(locale).add_Hm(),
      _full = DateFormat.yMMMMEEEEd(locale).add_Hm(),
      _numbers = NumberFormat.decimalPattern(locale);

  /// The formatters for the locale of the widget tree at [context].
  factory of(BuildContext context) => Formatters(
    Localizations.localeOf(context).toString(),
    toLocal: deviceTimeOverride,
  );

  /// The time zone the screens use instead of the one of the device, set by
  /// the golden tests so that a date reads the same on every machine. Never
  /// set by the app.
  @visibleForTesting
  static DateTime Function(int epochMillis)? deviceTimeOverride;

  final DateTime Function(int epochMillis) _toLocal;
  final DateFormat _compact;
  final DateFormat _full;
  final NumberFormat _numbers;

  static DateTime _deviceTime(int epochMillis) =>
      DateTime.fromMillisecondsSinceEpoch(epochMillis);

  /// Compact: weekday, day, month, year and time. For rows, banners and closing
  /// times.
  String dateTime(Instant instant) => _compact.format(_toLocal(instant));

  /// Complete: the whole weekday and month, and the time. For the header of a
  /// meeting.
  String fullDateTime(Instant instant) => _full.format(_toLocal(instant));

  /// A number with the grouping of the locale. For counts.
  String number(num value) => _numbers.format(value);
}
