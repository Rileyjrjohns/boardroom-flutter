import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/features/documents/presentation/error_messages.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/presentation/test_app.dart';

// The maps from a code to a text are exhaustive over their families and tell
// every code in both languages.

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final l10n = l10nOf(locale);

    group('in ${locale.languageCode}', () {
      test('tells every way opening a document can fail', () {
        final codes = [
          AuthenticationErrorCode.notAuthenticated.value,
          AuthenticationErrorCode.sessionExpired.value,
          AuthenticationErrorCode.appLocked.value,
          AuthenticationErrorCode.sessionChanged.value,
          StorageErrorCode.readFailed.value,
          RepositoryErrorCode.networkUnavailable.value,
          RepositoryErrorCode.unauthorized.value,
          RepositoryErrorCode.forbidden.value,
          RepositoryErrorCode.notFound.value,
          RepositoryErrorCode.unexpected.value,
          for (final code in ScreenProtectionErrorCode.values) code.value,
        ];
        for (final code in codes) {
          expect(documentErrorMessages, contains(code));
          expect(documentErrorMessage(l10n, code), isNotEmpty);
        }
        expect(documentErrorMessages.keys.toSet(), codes.toSet());
      });

      test('tells a code it does not know as unexpected', () {
        expect(
          documentErrorMessage(l10n, 'somethingNew'),
          documentErrorMessage(l10n, RepositoryErrorCode.unexpected.value),
        );
      });

      test('tells a screenshot and the start of a recording, and not the '
          'end of a recording', () {
        expect(
          captureNoticeMessage(l10n, ScreenCaptureKind.screenshotTaken),
          l10n.documentsDocumentCaptureScreenshot,
        );
        expect(
          captureNoticeMessage(l10n, ScreenCaptureKind.recordingStarted),
          l10n.documentsDocumentCaptureRecording,
        );
        expect(
          captureNoticeMessage(l10n, ScreenCaptureKind.recordingStopped),
          isNull,
        );
      });
    });
  }
}
