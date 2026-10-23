import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/constants.dart';
import 'package:boardroom/domain/shared/result.dart';

// Monitoring over Sentry, written and tested but not wired: the app starts with
// the console monitoring, and no Sentry SDK is a dependency of the project.
// `docs/monitoring.md` says how to turn it on.

/// A breadcrumb or an event of the SDK, as the JSON object it is sent as.
typedef SentryJson = Map<String, Object?>;

/// The keys of the JSON objects of the Sentry protocol this adapter reads and
/// writes: a breadcrumb, an event, the context of a report.
abstract final class SentryKey {
  /// Where a breadcrumb comes from.
  static const String category = 'category';

  /// The text of a breadcrumb or of an event.
  static const String message = 'message';

  /// The severity.
  static const String level = 'level';

  /// The data of a breadcrumb.
  static const String data = 'data';

  /// The tags of an event.
  static const String tags = 'tags';

  /// The extra data of an event.
  static const String extra = 'extra';

  /// The contexts of an event (device, operating system...).
  static const String contexts = 'contexts';

  /// The trail of breadcrumbs of an event.
  static const String breadcrumbs = 'breadcrumbs';

  /// The request an event was captured in.
  static const String request = 'request';

  /// The name of the machine.
  static const String serverName = 'server_name';

  /// The modules loaded by the application.
  static const String modules = 'modules';

  /// The user of an event.
  static const String user = 'user';

  /// The identifier of the user.
  static const String id = 'id';

  /// The structured message of an event.
  static const String logEntry = 'logentry';

  /// The exception of an event.
  static const String exception = 'exception';

  /// The exceptions of an event.
  static const String values = 'values';

  /// The text of an exception.
  static const String value = 'value';

  /// How reports are grouped.
  static const String fingerprint = 'fingerprint';
}

/// The part of the Sentry SDK this adapter uses. It is an interface, and not
/// the SDK used in place, so that this file does not import it (the project has
/// no Sentry dependency), the tests hand over a recording stand-in, and the SDK
/// can be replaced by changing the small class that implements this interface.
abstract interface class SentrySdk {
  /// Starts the SDK with the [options].
  void init(SentryOptions options);

  /// Leaves a breadcrumb on the trail that the next error report carries.
  void addBreadcrumb(SentryJson breadcrumb);

  /// Reports [exception], with the [context] of the report: the `level`, the
  /// `tags`, the `extra` data, the `fingerprint` and the `user`.
  void captureException(ReportedError exception, SentryJson context);
}

/// The error that is reported: its name is the code of the error, its message
/// the event (and the kind of failure).
final class ReportedError {
  /// Creates the report of an error named [name].
  const new({required this.name, required this.message});

  /// The code of the error.
  final String name;

  /// The event, and the kind of failure when the error has a cause.
  final String message;

  @override
  String toString() => '$name: $message';
}

/// What the SDK is started with.
final class SentryOptions {
  /// Creates the options of the SDK.
  const new({
    required this.dsn,
    required this.sendDefaultPii,
    required this.attachScreenshot,
    required this.attachViewHierarchy,
    required this.enableCaptureFailedRequests,
    required this.enableAutoPerformanceTracing,
    required this.maxBreadcrumbs,
    required this.beforeBreadcrumb,
    required this.beforeSend,
  });

  /// The address events are sent to.
  final String dsn;

  /// Whether the SDK adds personal data by default.
  final bool sendDefaultPii;

  /// Whether a screenshot goes with an error.
  final bool attachScreenshot;

  /// Whether the tree of the views goes with an error.
  final bool attachViewHierarchy;

  /// Whether the SDK reports failed requests, which quote their URL.
  final bool enableCaptureFailedRequests;

  /// Whether the SDK traces the performance of the app by itself (screen loads,
  /// requests, frames). Off: the app reports errors and its own events, and
  /// nothing about what the people do on its screens.
  final bool enableAutoPerformanceTracing;

  /// How many breadcrumbs an error report carries.
  final int maxBreadcrumbs;

  /// Called for every breadcrumb: `null` drops it.
  final SentryJson? Function(SentryJson breadcrumb) beforeBreadcrumb;

  /// Called for every event before it leaves the device.
  final SentryJson Function(SentryJson event) beforeSend;
}

/// The category of every breadcrumb the app leaves. The breadcrumbs of the SDK
/// have other ones.
const String breadcrumbCategory = 'boardroom';

/// The names of the tags an error is reported with: the event, and the code of
/// the error.
abstract final class SentryTag {
  /// The monitoring event.
  static const String event = 'event';

  /// The code of the error.
  static final String errorCode = LogAttribute.errorCode.value;
}

/// The key of the technical cause in the payload of an error.
const String _causeKey = 'cause';

/// The Sentry level of each level of the port, and of a captured error.
const String _infoLevel = 'info';
const String _warningLevel = 'warning';
const String _errorLevel = 'error';

/// How many breadcrumbs an error report carries: the last ones tell what led to
/// it.
const int _maxBreadcrumbs = 50;

/// Longer text is cut: an attribute is an identifier or a code, never a
/// paragraph.
const int _maxTextLength = 200;

/// The keys data may be sent under: the attribute names of the port, and
/// nothing else.
final Set<String> _allowedAttributeKeys = valuesOf(LogAttribute.values).toSet();

/// The tags that stay on an event: ours, and the attribute names.
final Set<String> _allowedTagKeys = {SentryTag.event, ..._allowedAttributeKeys};

/// The technical contexts the SDK adds, kept; any other context is dropped.
/// Each lists the fields that stay (none of them names a person: the name the
/// user gave to the device is not one). `null` keeps the context whole.
const Map<String, Set<String>?> _keptContexts = {
  'app': {
    'app_identifier',
    'app_name',
    'app_version',
    'app_build',
    'in_foreground',
  },
  'os': {'name', 'version', 'build', 'kernel_version'},
  'device': {'family', 'model', 'model_id', 'arch', 'simulator', 'orientation'},
  'runtime': {'name', 'version'},
  'culture': {'locale', 'timezone'},
  // The trace and span ids: random identifiers, with no field to filter.
  'trace': null,
};

/// `https://<public key>@<host>/<project id>`, with the optional port and path
/// of a relay.
final RegExp _dsnPattern = RegExp(
  r'^https://[A-Za-z0-9]+(?::[A-Za-z0-9]+)?@[A-Za-z0-9.-]+(?::\d+)?'
  r'(?:/[\w.~-]+)*/\d+$',
);

/// Whether the text has the shape of a Sentry DSN. The SDK is the judge of the
/// rest.
bool isSentryDsn(String value) => _dsnPattern.hasMatch(value);

/// The JSON object an object of the event is, or `null` when it is not one.
SentryJson? _objectOf(Object? value) =>
    value is Map<dynamic, dynamic> ? value.cast<String, Object?>() : null;

bool _isAttributeValue(Object? value) =>
    value is String || value is num || value is bool;

Object _limited(Object value) =>
    value is String && value.length > _maxTextLength
    ? value.substring(0, _maxTextLength)
    : value;

/// What of some data may leave the device: the entries whose key is an
/// attribute name of the port and whose value is a string, a number or a
/// boolean. Everything else is dropped, whoever put it there.
Map<String, Object> allowedAttributes(Map<String, Object?>? source) => {
  for (final MapEntry(:key, :value) in (source ?? const {}).entries)
    if (_allowedAttributeKeys.contains(key) && _isAttributeValue(value))
      key: _limited(value!),
};

SentryJson _scrubContext(SentryJson? context, Set<String>? kept) {
  if (context == null) {
    return {};
  }
  return kept == null
      ? {...context}
      : {
          for (final MapEntry(:key, :value) in context.entries)
            if (kept.contains(key)) key: value,
        };
}

SentryJson _scrubContexts(SentryJson? contexts) => {
  for (final MapEntry(:key, :value) in (contexts ?? const {}).entries)
    if (_keptContexts.containsKey(key))
      key: _scrubContext(_objectOf(value), _keptContexts[key]),
};

bool _isOwnBreadcrumb(SentryJson breadcrumb) =>
    breadcrumb[SentryKey.category] == breadcrumbCategory;

SentryJson _scrubBreadcrumb(SentryJson breadcrumb) => {
  ...breadcrumb,
  SentryKey.data: allowedAttributes(_objectOf(breadcrumb[SentryKey.data])),
};

/// `beforeBreadcrumb`: the automatic breadcrumbs of the SDK (console, requests,
/// taps) are dropped.
SentryJson? keepOwnBreadcrumb(SentryJson breadcrumb) =>
    _isOwnBreadcrumb(breadcrumb) ? _scrubBreadcrumb(breadcrumb) : null;

/// `beforeSend`: nothing leaves the device that is not an allowed attribute.
/// Tags, extra data and breadcrumb data keep the attribute names of the port
/// only; the only user field is the id (never an email, a name, an address);
/// the request (URL, headers, cookies) goes; so do the contexts that are not
/// technical. So do the free texts: the message of the event, and the message
/// of an error the app did not report itself (an uncaught exception), which may
/// quote what the code was handling. The type and the stack of such an error
/// stay, which is what a crash is read from.
SentryJson scrubEvent(SentryJson event) {
  final tags = _objectOf(event[SentryKey.tags]) ?? const <String, Object?>{};
  final own = tags[SentryTag.event] != null;
  final breadcrumbs = event[SentryKey.breadcrumbs];
  final scrubbed =
      <String, Object?>{
          ...event,
          SentryKey.tags: {
            for (final MapEntry(:key, :value) in tags.entries)
              if (_allowedTagKeys.contains(key)) key: value,
          },
          SentryKey.extra: allowedAttributes(_objectOf(event[SentryKey.extra])),
          SentryKey.contexts: _scrubContexts(
            _objectOf(event[SentryKey.contexts]),
          ),
          SentryKey.breadcrumbs: [
            if (breadcrumbs is List<dynamic>)
              for (final breadcrumb in breadcrumbs)
                if (_objectOf(breadcrumb) case final json?
                    when _isOwnBreadcrumb(json))
                  _scrubBreadcrumb(json),
          ],
        }
        ..remove(SentryKey.request)
        ..remove(SentryKey.serverName)
        ..remove(SentryKey.modules)
        ..remove(SentryKey.user);
  final userId = _objectOf(event[SentryKey.user])?[SentryKey.id];
  if (userId != null) {
    scrubbed[SentryKey.user] = {SentryKey.id: '$userId'};
  }

  // An exception event has no message of its own; one that does is a free text.
  scrubbed
    ..remove(SentryKey.message)
    ..remove(SentryKey.logEntry);
  if (!own) {
    final values = _objectOf(event[SentryKey.exception])?[SentryKey.values];
    if (values is List<dynamic>) {
      scrubbed[SentryKey.exception] = {
        SentryKey.values: [
          for (final value in values)
            {
              for (final MapEntry(:key, value: field)
                  in (_objectOf(value) ?? const <String, Object?>{}).entries)
                if (key != SentryKey.value) key: field,
            },
        ],
      };
    }
  }
  return scrubbed;
}

/// The options the SDK starts with. A function of the address, for the test
/// that reads them.
SentryOptions sentryOptions(String dsn) => SentryOptions(
  dsn: dsn,
  sendDefaultPii: false,
  // The screens show confidential material: no picture of them, no tree of
  // their views.
  attachScreenshot: false,
  attachViewHierarchy: false,
  // The reports of failed requests quote their URL.
  enableCaptureFailedRequests: false,
  enableAutoPerformanceTracing: false,
  maxBreadcrumbs: _maxBreadcrumbs,
  beforeBreadcrumb: keepOwnBreadcrumb,
  beforeSend: scrubEvent,
);

/// The error that is reported: its name is the code, its message the event (and
/// the kind of failure).
ReportedError _reportedError(MonitoringEvent event, AppError error) {
  final cause = error.payload[_causeKey];
  return ReportedError(
    name: error.code,
    message: cause is String
        ? '${event.value}: ${_limited(cause)}'
        : event.value,
  );
}

Map<String, Object?> _namedAttributes(LogAttributes? attributes) => {
  for (final MapEntry(:key, :value) in (attributes ?? const {}).entries)
    key.value: value,
};

/// Monitoring over Sentry: the logs are breadcrumbs, left on the trail that the
/// next error report carries, and a captured error is an exception reported
/// with its event and its code as tags, and grouped by the two. The attributes
/// of the port are the only data that goes along, and the user is known by the
/// id the port gives, if it gives one. Nothing sent here is a name, an email, a
/// path or a URL: the port forbids it, and `beforeSend` removes whatever else
/// the SDK would add.
///
/// Fire and forget, as the port requires: nothing is returned and nothing
/// throws, whatever the SDK does.
final class SentryMonitoring implements Monitoring {
  /// Creates monitoring that reports through [sdk].
  const new(SentrySdk sdk) : _sdk = sdk;

  final SentrySdk _sdk;

  @override
  void log(LogLevel level, MonitoringEvent event, [LogAttributes? attributes]) {
    try {
      _sdk.addBreadcrumb({
        SentryKey.category: breadcrumbCategory,
        SentryKey.message: event.value,
        SentryKey.level: switch (level) {
          LogLevel.info => _infoLevel,
          LogLevel.warn => _warningLevel,
        },
        SentryKey.data: allowedAttributes(_namedAttributes(attributes)),
      });
      // Monitoring must never break the code it observes.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }

  @override
  void captureError(
    MonitoringEvent event,
    AppError error, [
    LogAttributes? attributes,
  ]) {
    try {
      final data = allowedAttributes(_namedAttributes(attributes));
      final userId = data[LogAttribute.userId.value];
      _sdk.captureException(_reportedError(event, error), {
        SentryKey.level: _errorLevel,
        SentryKey.tags: {
          SentryTag.event: event.value,
          SentryTag.errorCode: error.code,
        },
        SentryKey.extra: data,
        SentryKey.fingerprint: [event.value, error.code],
        if (userId != null) SentryKey.user: {SentryKey.id: '$userId'},
      });
      // Monitoring must never break the code it observes.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }
}

/// Why Sentry could not be started.
enum SentryStartFailure implements StableValue {
  /// The address is not a DSN.
  invalidDsn('invalidDsn'),

  /// The SDK threw when it started.
  sdkFailed('sdkFailed');

  new(this.value);

  @override
  final String value;
}

/// Starts the SDK for the address, and gives the monitoring over it; or says
/// why it could not, and never throws. A caller that gets a failure keeps the
/// monitoring it had.
Result<Monitoring, SentryStartFailure> createSentryMonitoring(
  String dsn,
  SentrySdk sdk,
) {
  if (!isSentryDsn(dsn)) {
    return err(SentryStartFailure.invalidDsn);
  }
  try {
    sdk.init(sentryOptions(dsn));
    // The SDK is a native module: whatever it throws is a failure to start.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return err(SentryStartFailure.sdkFailed);
  }
  return ok(SentryMonitoring(sdk));
}
