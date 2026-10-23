import 'package:boardroom/app/composition/settings.dart';
import 'package:boardroom/app/container/container_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/core/infrastructure/http/api_base_url.dart';
import 'package:meta/meta.dart';

/// The two ways of wiring the app: against the simulated server (the fixture
/// server, in process) with caches in memory, or against the real API with the
/// database and the keychain of the device. The values are what the
/// `BOARDROOM_ADAPTERS` define accepts.
enum AdaptersKind implements StableValue {
  /// The development configuration (`mock` in the React Native app).
  dev('dev'),

  /// The real adapters: the HTTP API, the encrypted database and the device.
  http('http');

  new(this.value);

  @override
  final String value;
}

/// How the app is wired. A sealed family: add a member, and the compiler lists
/// every `switch` to extend.
@immutable
sealed class AppConfiguration {
  /// Creates a configuration. [sentryDsn] is the address of the crash reporter
  /// the build was given, if any: absent means off, and the events go to the
  /// console (see `createMonitoring`).
  const new({this.sentryDsn});

  /// The address of the crash reporter, trimmed, or null.
  final String? sentryDsn;

  /// Which adapters this configuration wires.
  AdaptersKind get kind;
}

/// The app against the simulated server and the in-memory caches.
final class DevConfiguration extends AppConfiguration {
  /// Creates the development configuration. The defaults are the values of
  /// `settings.dart`.
  new({
    super.sentryDsn,
    this.startSignedIn = devStartsSignedIn,
    DurationMillis? latency,
    DurationMillis? sessionLifetime,
  }) : latency = latency ?? devSimulatedLatency,
       sessionLifetime = sessionLifetime ?? devSessionLifetime;

  /// Whether the first account of the simulation is signed in at start. Named,
  /// so that the day it goes away is visible.
  final bool startSignedIn;

  /// How long the simulated server takes to answer.
  final DurationMillis latency;

  /// How long a session of the simulated server lasts, from the sign-in.
  final DurationMillis sessionLifetime;

  @override
  AdaptersKind get kind => AdaptersKind.dev;

  @override
  bool operator ==(Object other) =>
      other is DevConfiguration &&
      other.sentryDsn == sentryDsn &&
      other.startSignedIn == startSignedIn &&
      other.latency == latency &&
      other.sessionLifetime == sessionLifetime;

  @override
  int get hashCode =>
      Object.hash(sentryDsn, startSignedIn, latency, sessionLifetime);
}

/// The app against the real adapters: the HTTP API, the encrypted database, the
/// secure storage and the device.
final class HttpConfiguration extends AppConfiguration {
  /// Creates the real configuration.
  const new({
    required this.baseUrl,
    required this.requestTimeout,
    required this.allowDevicePasscode,
    super.sentryDsn,
  });

  /// The address of the API: `https`, or `http` for the machine itself, with no
  /// trailing slash.
  final String baseUrl;

  /// How long a request may take before it counts as a network failure.
  final DurationMillis requestTimeout;

  /// Whether the passcode of the device is accepted when the biometrics fail.
  final bool allowDevicePasscode;

  @override
  AdaptersKind get kind => AdaptersKind.http;

  @override
  bool operator ==(Object other) =>
      other is HttpConfiguration &&
      other.sentryDsn == sentryDsn &&
      other.baseUrl == baseUrl &&
      other.requestTimeout == requestTimeout &&
      other.allowDevicePasscode == allowDevicePasscode;

  @override
  int get hashCode =>
      Object.hash(sentryDsn, baseUrl, requestTimeout, allowDevicePasscode);
}

/// The settings of the environment, raw: the app reads them once and passes
/// them on, the container reads nothing itself. Every one of them is validated
/// in [parseConfiguration], and nowhere else.
@immutable
final class RawSettings {
  /// Creates the settings of a test or of a caller that read them elsewhere.
  const new({
    this.adapters,
    this.apiBaseUrl,
    this.sentryDsn,
    this.devStartsSignedIn,
    this.requestTimeoutMillis,
    this.allowDevicePasscode,
  });

  /// Reads the settings from the `--dart-define` values of the build:
  /// `BOARDROOM_ADAPTERS`, `BOARDROOM_API_BASE_URL`, `BOARDROOM_SENTRY_DSN` and
  /// `BOARDROOM_DEV_STARTS_SIGNED_IN`. A value that is not defined is blank
  /// (`devStartsSignedIn` is then null). The request timeout and the passcode
  /// fallback are not read from the build: their defaults are the values of
  /// `settings.dart`.
  const new fromEnvironment()
    : adapters = const String.fromEnvironment(adaptersDefine),
      apiBaseUrl = const String.fromEnvironment(apiBaseUrlDefine),
      sentryDsn = const String.fromEnvironment(sentryDsnDefine),
      devStartsSignedIn = const bool.hasEnvironment(devStartsSignedInDefine)
          ? const bool.fromEnvironment(devStartsSignedInDefine)
          : null,
      requestTimeoutMillis = null,
      allowDevicePasscode = null;

  /// Name of the define that chooses the adapters: `dev` or `http`.
  static const String adaptersDefine = 'BOARDROOM_ADAPTERS';

  /// Name of the define that gives the address of the API. Required for
  /// `http`, ignored by `dev`.
  static const String apiBaseUrlDefine = 'BOARDROOM_API_BASE_URL';

  /// Name of the define that gives the address of the crash reporter.
  static const String sentryDsnDefine = 'BOARDROOM_SENTRY_DSN';

  /// Name of the define that starts the development configuration signed in.
  static const String devStartsSignedInDefine =
      'BOARDROOM_DEV_STARTS_SIGNED_IN';

  /// The adapters: `dev` or `http`.
  final String? adapters;

  /// Where the API is. Required for `http`, ignored by `dev`.
  final String? apiBaseUrl;

  /// The address of the crash reporter. Blank or missing: the monitoring is the
  /// console. It is not validated here: `createMonitoring` checks it, and falls
  /// back on the console for a bad one, since monitoring must not decide
  /// whether the app starts.
  final String? sentryDsn;

  /// Starts the development configuration signed in as the first account.
  final bool? devStartsSignedIn;

  /// The request timeout in milliseconds, replaced: for the tests of its
  /// validation, and for a build that needs another one. It is an object
  /// because the validation is what says whether it is a whole number.
  final Object? requestTimeoutMillis;

  /// Whether the passcode of the device is accepted. An object, for the same
  /// reason: it must be a boolean.
  final Object? allowDevicePasscode;
}

/// Turns the settings of the environment into a configuration. A missing or
/// blank adapters setting is the development configuration in a development
/// build, where the simulated server is the sensible default, and an error
/// everywhere else (`missingAdaptersSetting`): a release build must be told
/// what it talks to, and must not start on a simulated server because someone
/// forgot a define. The value is trimmed and its case ignored. Anything else
/// that is not a known way of wiring is an error, not a silent fallback: a typo
/// must not start the demo against the wrong thing.
///
/// The real configuration needs the address of the API (`missingApiBaseUrl`,
/// `invalidApiBaseUrl`, and `insecureApiBaseUrl` for `http` outside a
/// development build, except for this machine), a request timeout within
/// bounds and a yes or no for the passcode fallback. Each is an error with a
/// code of its own, so that the screen of a failed start says what to fix.
Result<AppConfiguration, ContainerError> parseConfiguration(
  RawSettings settings, {
  required bool development,
}) {
  final parsed = _parseAdapters(settings, development: development);
  if (parsed case Err(:final error)) {
    return err(error);
  }
  final configuration = (parsed as Ok<AppConfiguration, ContainerError>).value;

  final sentryDsn = trimText(settings.sentryDsn ?? '');
  if (sentryDsn.isEmpty) {
    return ok(configuration);
  }
  return ok(switch (configuration) {
    DevConfiguration() => DevConfiguration(
      sentryDsn: sentryDsn,
      startSignedIn: configuration.startSignedIn,
      latency: configuration.latency,
      sessionLifetime: configuration.sessionLifetime,
    ),
    HttpConfiguration() => HttpConfiguration(
      sentryDsn: sentryDsn,
      baseUrl: configuration.baseUrl,
      requestTimeout: configuration.requestTimeout,
      allowDevicePasscode: configuration.allowDevicePasscode,
    ),
  });
}

Result<AppConfiguration, ContainerError> _parseAdapters(
  RawSettings settings, {
  required bool development,
}) {
  final setting = trimText(settings.adapters ?? '');
  if (setting.isEmpty) {
    return development
        ? ok(_devConfiguration(settings))
        : err(missingAdaptersSetting());
  }

  final kind = findConstant(AdaptersKind.values, setting.toLowerCase());
  return switch (kind) {
    AdaptersKind.dev => ok(_devConfiguration(settings)),
    AdaptersKind.http => _parseHttpConfiguration(
      settings,
      development: development,
    ),
    null => err(invalidAdaptersSetting(setting)),
  };
}

DevConfiguration _devConfiguration(RawSettings settings) => DevConfiguration(
  startSignedIn: settings.devStartsSignedIn ?? devStartsSignedIn,
);

Result<AppConfiguration, ContainerError> _parseHttpConfiguration(
  RawSettings settings, {
  required bool development,
}) {
  final baseUrl = parseApiBaseUrl(
    settings.apiBaseUrl,
    BaseUrlEnvironment(development: development),
  );
  final String address;
  switch (baseUrl) {
    case Ok(:final value):
      address = value;
    case Err(:final error):
      return err(switch (error) {
        ApiBaseUrlError.missing => missingApiBaseUrl(),
        ApiBaseUrlError.malformed => invalidApiBaseUrl(),
        ApiBaseUrlError.insecure => insecureApiBaseUrl(),
      });
  }

  final requestTimeout = settings.requestTimeoutMillis == null
      ? ok<DurationMillis>(httpRequestTimeout)
      : _timeoutOf(settings.requestTimeoutMillis!);
  final DurationMillis timeout;
  switch (requestTimeout) {
    case Ok(:final value):
      timeout = value;
    case Err(:final error):
      return err(error);
  }

  final passcode = settings.allowDevicePasscode ?? allowDevicePasscodeFallback;
  if (passcode is! bool) {
    return err(invalidBiometricFallback());
  }

  return ok(
    HttpConfiguration(
      baseUrl: address,
      requestTimeout: timeout,
      allowDevicePasscode: passcode,
    ),
  );
}

Result<DurationMillis, ContainerError> _timeoutOf(Object millis) {
  if (millis is! num) {
    return err(invalidRequestTimeout());
  }
  final duration = durationFromMillis(millis);
  if (duration case Ok(:final value)
      when value >= minHttpRequestTimeout && value <= maxHttpRequestTimeout) {
    return ok(value);
  }
  return err(invalidRequestTimeout());
}
