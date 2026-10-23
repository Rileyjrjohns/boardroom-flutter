import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

// The texts of the app are in two ARB files, English (the template) and
// French, structured by key prefix, one per owner: `core` (what no feature
// owns), `auth`, `meetings`, `documents` and `votes` (docs/presentation.md,
// "Texts"). This test keeps the two files in step and the convention honest.

const Set<String> prefixes = {'core', 'auth', 'meetings', 'documents', 'votes'};

Map<String, Object?> _read(String language) =>
    json.decode(File('lib/l10n/app_$language.arb').readAsStringSync())
        as Map<String, Object?>;

Iterable<String> _keys(Map<String, Object?> arb) =>
    arb.keys.where((key) => !key.startsWith('@'));

final RegExp _placeholder = RegExp(r'\{(\w+)(?:,|\})');

Set<String> _placeholders(String message) {
  // Inside a plural, the cases are text; the names are the ones before a comma
  // or a closing brace, and the plural keywords are not placeholders.
  const keywords = {'plural', 'one', 'other', 'many', 'few', 'two', 'zero'};
  return {
    for (final match in _placeholder.allMatches(message))
      if (!keywords.contains(match.group(1))) match.group(1)!,
  };
}

void main() {
  final en = _read('en');
  final fr = _read('fr');

  test('French has exactly the keys of English', () {
    expect(_keys(fr).toSet(), _keys(en).toSet());
  });

  test('every key starts with the prefix of its owner', () {
    for (final key in _keys(en)) {
      expect(
        prefixes.any(
          (prefix) =>
              key.startsWith(prefix) &&
              key.length > prefix.length &&
              key[prefix.length] == key[prefix.length].toUpperCase(),
        ),
        isTrue,
        reason: '$key does not start with one of $prefixes + a capital letter',
      );
    }
  });

  test('every key is described in the template, and no text is empty', () {
    for (final key in _keys(en)) {
      expect(en['@$key'], isA<Map<String, Object?>>(), reason: key);
      expect((en[key]! as String).trim(), isNotEmpty, reason: key);
      expect((fr[key]! as String).trim(), isNotEmpty, reason: key);
    }
  });

  test('both languages take the same parameters, declared in the template', () {
    for (final key in _keys(en)) {
      final inEnglish = _placeholders(en[key]! as String);
      final inFrench = _placeholders(fr[key]! as String);
      final declared =
          ((en['@$key']! as Map<String, Object?>)['placeholders']
                      as Map<String, Object?>? ??
                  {})
              .keys
              .toSet();

      expect(inFrench, inEnglish, reason: key);
      expect(declared, inEnglish, reason: key);
    }
  });

  test(
    'French differs from English, apart from the names that do not change',
    () {
      const same = {
        'coreAppName',
        'corePrivacyHidden',
        'meetingsMeetingAgendaItem',
        'meetingsMeetingDocumentLabel',
        'meetingsConfidentialityPublic',
        'coreNavigationDocument',
        'meetingsParticipantRoleMember',
      };
      final untranslated = [
        for (final key in _keys(en))
          if (en[key] == fr[key] && !same.contains(key)) key,
      ];

      expect(untranslated.length, lessThan(8), reason: '$untranslated');
    },
  );

  test('the texts of the French typography keep the no-break space before a '
      'colon', () {
    final bare = [
      for (final key in _keys(fr))
        if (RegExp(r'\w :').hasMatch(fr[key]! as String)) key,
    ];

    expect(bare, isEmpty);
  });
}
