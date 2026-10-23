import 'package:boardroom/app/app.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Pumps the app in [locale] and returns the strings of that language, read
  // from the generated class so the test holds no user-facing literal.
  Future<AppLocalizations> pumpApp(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(BoardroomApp(locale: locale));
    await tester.pumpAndSettle();
    return lookupAppLocalizations(locale);
  }

  testWidgets('shows the home screen texts in English', (tester) async {
    final l10n = await pumpApp(tester, const Locale('en'));

    expect(find.text(l10n.appTitle), findsOneWidget);
    expect(find.text(l10n.homeComingSoon), findsOneWidget);
  });

  testWidgets('shows the home screen texts in French', (tester) async {
    final l10n = await pumpApp(tester, const Locale('fr'));

    expect(find.text(l10n.appTitle), findsOneWidget);
    expect(find.text(l10n.homeComingSoon), findsOneWidget);
  });

  testWidgets('French and English texts differ', (tester) async {
    final en = lookupAppLocalizations(const Locale('en'));
    final fr = lookupAppLocalizations(const Locale('fr'));

    expect(fr.homeComingSoon, isNot(en.homeComingSoon));
  });

  testWidgets('falls back to English for an unsupported language', (
    tester,
  ) async {
    await tester.pumpWidget(const BoardroomApp(locale: Locale('de')));
    await tester.pumpAndSettle();

    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(en.homeComingSoon), findsOneWidget);
  });
}
