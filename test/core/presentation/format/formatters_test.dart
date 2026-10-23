import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../../support/builders/builders.dart';
import '../../../support/presentation/test_app.dart';

// The formatters of the screens: compact and full date and time, and numbers
// with the grouping of the locale. The zone is fixed to UTC so that the text is
// the same on every machine.

DateTime _utc(int epochMillis) =>
    DateTime.fromMillisecondsSinceEpoch(epochMillis, isUtc: true);

void main() {
  setUpAll(initializeDateFormatting);

  test('writes a compact date and time in English and French', () {
    final en = Formatters('en', toLocal: _utc);
    final fr = Formatters('fr', toLocal: _utc);

    expect(en.dateTime(now), contains('2030'));
    expect(en.dateTime(now), isNot(fr.dateTime(now)));
    expect(fr.dateTime(now), contains('2030'));
  });

  test('writes the whole weekday and month in the full form', () {
    final full = Formatters('en', toLocal: _utc).fullDateTime(now);
    final compact = Formatters('en', toLocal: _utc).dateTime(now);

    expect(full.length, greaterThan(compact.length));
  });

  test('groups the digits as the locale wants', () {
    expect(Formatters('en').number(1000), '1,000');
    expect(Formatters('fr').number(1000), isNot('1,000'));
    expect(Formatters('fr').number(1000), contains('000'));
  });

  testWidgets('follows the locale of the tree', (tester) async {
    late Formatters formatters;
    await pumpScreen(
      tester,
      Builder(
        builder: (context) {
          formatters = Formatters.of(context);
          return const SizedBox.shrink();
        },
      ),
      locale: const Locale('fr'),
    );

    expect(formatters.number(1000), Formatters('fr').number(1000));
  });
}
