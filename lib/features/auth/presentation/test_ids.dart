// The test ids of the session screens: the restore failure, the sign-in, the
// lock and the sign-out, declared by the feature that owns the screens and put
// together with the others by `lib/app/test_ids.dart`. Pure Dart, so that the
// conformance test of the specification can read them. The widgets set them as
// `Key(id)`; the values are the ones of docs/spec/screens.md.

/// The test ids of the session screens: the restore failure, the sign-in, the
/// lock and the sign-out.
abstract final class AuthTestIds {
  /// The error state of a restore that failed.
  static const String restoreError = 'restore-error';

  /// The sign-out escape of the restore failure.
  static const String restoreForget = 'restore-forget';

  /// The failure of that sign-out.
  static const String restoreForgetError = 'restore-forget-error';

  /// Why the user was sent to the sign-in or lock screen.
  static const String sessionNotice = 'session-notice';

  /// The sign-in screen.
  static const String signInScreen = 'sign-in-screen';

  /// The email field.
  static const String signInEmail = 'sign-in-email';

  /// The error under the email field.
  static const String signInEmailError = 'sign-in-email-error';

  /// The password field.
  static const String signInPassword = 'sign-in-password';

  /// The error under the password field.
  static const String signInPasswordError = 'sign-in-password-error';

  /// A failure that is not about a field.
  static const String signInError = 'sign-in-error';

  /// The submit button.
  static const String signInSubmit = 'sign-in-submit';

  /// The lock screen.
  static const String lockScreen = 'lock-screen';

  /// The unlock button.
  static const String lockUnlock = 'lock-unlock';

  /// The last unlock failure.
  static const String lockError = 'lock-error';

  /// The sign-out button of the lock screen.
  static const String lockSignOut = 'lock-sign-out';

  /// The sign-out button of the header actions.
  static const String signOutButton = 'sign-out-button';

  /// The sign-out dialog.
  static const String signOutDialog = 'sign-out-dialog';

  /// The line about the votes that wait.
  static const String signOutPending = 'sign-out-pending';

  /// The sign-out failure.
  static const String signOutError = 'sign-out-error';

  /// The confirm button.
  static const String signOutConfirm = 'sign-out-confirm';

  /// The cancel button.
  static const String signOutCancel = 'sign-out-cancel';
}
