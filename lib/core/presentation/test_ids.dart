// The test ids of the shared components, referenced by the components and by
// their tests. The widgets set them as `Key(id)`, so the same flows find them
// as on the React Native app (docs/spec/screens.md). Pure Dart, so that the
// conformance test can read them. The test ids of a screen are declared by the
// feature that owns it; `lib/app/test_ids.dart` puts them all together.

/// The test ids of the core.
abstract final class CoreTestIds {
  /// The banner area, when it has at least one fact to tell.
  static const String statusBanner = 'status-banner';

  /// The line that says the device is offline.
  static const String offlineBanner = 'offline-banner';

  /// The line that says the screen shows a saved copy.
  static const String staleBanner = 'stale-banner';

  /// The retry button of an error state or an inline error.
  static const String retryButton = 'retry-button';

  /// A refresh that failed with content on screen.
  static const String refreshError = 'refresh-error';

  /// The demo offline switch bar.
  static const String demoPanel = 'demo-panel';

  /// The demo accounts panel of the sign-in screen.
  static const String demoAccounts = 'demo-accounts';

  /// The switch row inside the demo panel.
  static const String demoOfflineSwitch = 'demo-offline-switch';

  /// The privacy cover.
  static const String privacyCover = 'privacy-cover';

  /// The container of the content of the app.
  static const String appContent = 'app-content';

  /// The notice that local data was reset.
  static const String localDataResetNotice = 'local-data-reset-notice';

  /// The dismiss button of that notice.
  static const String localDataResetDismiss = 'local-data-reset-dismiss';

  /// The loading state of the start.
  static const String startupLoading = 'startup-loading';

  /// The screen of a start that failed.
  static const String startupFailure = 'startup-failure';

  /// The error boundary.
  static const String errorBoundary = 'error-boundary';
}

const String _demoAccountPrefix = 'demo-account-';

/// The button that fills the credentials of a demo account, named after its
/// email address.
String demoAccountTestId(String email) => '$_demoAccountPrefix$email';
