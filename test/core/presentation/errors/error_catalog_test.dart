import 'package:boardroom/app/composition/retryable_codes.dart';
import 'package:boardroom/app/error_catalog.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/errors/error_catalog.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/presentation/test_app.dart';

// Every code of the core and of the session has a text, in both languages, and
// the catalog tells which of them a second try can fix.

void main() {
  const locales = [Locale('en'), Locale('fr')];
  final catalog = createAppErrorCatalog();

  final coreCodes = [
    ...RepositoryErrorCode.values.map((code) => code.value),
    ...StorageErrorCode.values.map((code) => code.value),
    ...ValidationErrorCode.values.map((code) => code.value),
  ];
  final sessionCodes = AuthenticationErrorCode.values.map((c) => c.value);

  test('has a text for every code of the core and of the session', () {
    for (final code in [...coreCodes, ...sessionCodes]) {
      expect(catalog.has(code), isTrue, reason: code);
    }
  });

  test('tells every code differently in each language, never empty', () {
    for (final locale in locales) {
      final l10n = l10nOf(locale);
      final texts = {
        for (final code in [...coreCodes, ...sessionCodes])
          code: catalog.messageOf(l10n, code),
      };

      expect(texts.values.every((text) => text.trim().isNotEmpty), isTrue);
      expect(texts.values.toSet().length, texts.length, reason: '$locale');
    }
  });

  test('reads a code with no text as unexpected', () {
    final l10n = l10nOf();

    expect(catalog.has('somethingNew'), isFalse);
    expect(
      catalog.messageOf(l10n, 'somethingNew'),
      catalog.messageOf(l10n, 'unexpected'),
    );
  });

  test('says which codes a second try can fix, the specification ones', () {
    for (final code in [...coreCodes, ...sessionCodes]) {
      expect(catalog.isRetryableCode(code), isRetryableCode(code));
    }
    expect(retryableCodes, {
      'networkUnavailable',
      'unexpected',
      'storageReadFailed',
      'screenProtectionFailed',
    });
  });

  test('must tell unexpected', () {
    expect(
      () => ErrorCatalog(messages: const {}, isRetryableCode: (_) => false),
      throwsA(isA<AssertionError>()),
    );
  });
}
