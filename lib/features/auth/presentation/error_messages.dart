import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/errors/error_catalog.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:boardroom/l10n/app_localizations.dart';

// The domain and the application speak in codes and carry no text. These maps
// are where a code of the session becomes a text. Each is a map from the stable
// string of the code, and a test checks that every code of its family has an
// entry.

/// What the failures of the session say, on every screen that can meet them (a
/// screen of the open app shows them as the error of what it was loading; the
/// sign-in and lock screens show them as the reason the user was sent back).
/// The app puts them in its error catalog next to the core's.
final Map<String, ErrorMessage> sessionErrorMessages = Map.unmodifiable({
  AuthenticationErrorCode.notAuthenticated.value: (AppLocalizations l) =>
      l.coreErrorsNotAuthenticated,
  AuthenticationErrorCode.sessionExpired.value: (AppLocalizations l) =>
      l.coreErrorsSessionExpired,
  AuthenticationErrorCode.appLocked.value: (AppLocalizations l) =>
      l.coreErrorsAppLocked,
  AuthenticationErrorCode.sessionChanged.value: (AppLocalizations l) =>
      l.coreErrorsSessionChanged,
  AuthenticationErrorCode.invalidCredentials.value: (AppLocalizations l) =>
      l.coreErrorsInvalidCredentials,
});

/// The text of the system prompt that asks for a biometric proof.
String biometricPromptMessage(AppLocalizations l10n, BiometricReason reason) =>
    switch (reason) {
      BiometricReason.unlockApp => l10n.authBiometricUnlockApp,
      BiometricReason.confirmVote => l10n.authBiometricConfirmVote,
    };

/// What each outcome of the biometric prompt says on the lock screen.
final Map<String, ErrorMessage> unlockErrorMessages = Map.unmodifiable({
  BiometricErrorCode.unavailable.value: (AppLocalizations l) =>
      l.authUnlockErrorsBiometricUnavailable,
  BiometricErrorCode.notEnrolled.value: (AppLocalizations l) =>
      l.authUnlockErrorsBiometricNotEnrolled,
  BiometricErrorCode.cancelled.value: (AppLocalizations l) =>
      l.authUnlockErrorsBiometricCancelled,
  BiometricErrorCode.failed.value: (AppLocalizations l) =>
      l.authUnlockErrorsBiometricFailed,
  BiometricErrorCode.lockedOut.value: (AppLocalizations l) =>
      l.authUnlockErrorsBiometricLockedOut,
  RepositoryErrorCode.unexpected.value: (AppLocalizations l) =>
      l.coreErrorsUnexpected,
});

/// The text of the failure of an unlock, `unexpected` for a code with none.
String unlockErrorMessage(AppLocalizations l10n, String code) =>
    (unlockErrorMessages[code] ??
    unlockErrorMessages[RepositoryErrorCode.unexpected.value]!)(l10n);

/// What a sign-in that was refused says. A badly formed field is told next to
/// the field instead.
final Map<String, ErrorMessage> signInErrorMessages = Map.unmodifiable({
  ValidationErrorCode.validation.value: (AppLocalizations l) =>
      l.coreErrorsValidation,
  AuthenticationErrorCode.invalidCredentials.value: (AppLocalizations l) =>
      l.coreErrorsInvalidCredentials,
  RepositoryErrorCode.networkUnavailable.value: (AppLocalizations l) =>
      l.coreErrorsNetworkUnavailable,
  RepositoryErrorCode.unexpected.value: (AppLocalizations l) =>
      l.coreErrorsUnexpected,
  StorageErrorCode.writeFailed.value: (AppLocalizations l) =>
      l.coreErrorsStorageWriteFailed,
});

/// The text of the failure of a sign-in, `unexpected` for a code with none.
String signInErrorMessage(AppLocalizations l10n, String code) =>
    (signInErrorMessages[code] ??
    signInErrorMessages[RepositoryErrorCode.unexpected.value]!)(l10n);

/// The message of a refused email: the rule decides it.
String emailRuleMessage(AppLocalizations l10n, ValidationRule rule) =>
    switch (rule) {
      ValidationRule.required => l10n.authSignInEmailRequired,
      ValidationRule.tooLong => l10n.authSignInEmailTooLong,
      _ => l10n.authSignInEmailInvalid,
    };

/// The message of a refused password: always the same.
String passwordRuleMessage(AppLocalizations l10n) =>
    l10n.authSignInPasswordRequired;
