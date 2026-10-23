# Monitoring

The application reports what happens through the `Monitoring` port (`lib/application/ports/monitoring.dart`): `log` for an event and `captureError` for a failure, both fire and forget, both taking only the events and attribute names of the port. No message, no name, no email, no path and no URL ever goes through it.

Two adapters implement it in `lib/infrastructure/monitoring`:

| Adapter | Where it writes | State |
| ------- | --------------- | ----- |
| `ConsoleMonitoring` | the console of the process: one line per event, `<channel> [boardroom] <event> {<attributes>}`, where the channel is `info`, `warn` or `error` (the three channels of the console in React Native, which one standard output cannot tell apart) | The adapter of development and of the demo. It is the one the composition root uses. |
| `SentryMonitoring` | Sentry: a log is a breadcrumb, a captured error is an exception tagged with its event and its code | Written and tested, **disabled**: the project has no Sentry dependency, so nothing is sent anywhere. |

Neither adapter ever throws, whatever the console or the SDK does.

## What `SentryMonitoring` guarantees

It is the same adapter as in the React Native app, with the same rules. They live in plain functions, tested on their own (`test/infrastructure/monitoring/sentry_monitoring_test.dart`):

- `allowedAttributes`: only the attribute names of the port, only strings, numbers and booleans, texts cut at 200 characters.
- `keepOwnBreadcrumb` (`beforeBreadcrumb`): the automatic breadcrumbs of the SDK (console, requests, taps) are dropped; ours keep their allowed data only.
- `scrubEvent` (`beforeSend`): tags, extra data and breadcrumb data keep the attribute names of the port; the only user field is the id; the request, the server name, the modules and the contexts that are not technical are removed; so are the free texts (the message of the event, and the message of an error the app did not report itself).
- `sentryOptions`: no default personal data, no screenshot, no view hierarchy, no report of failed requests (they quote their URL), no automatic performance tracing, 50 breadcrumbs. As in React Native there is no sample rate for traces, so the SDK sends none.

The adapter does not import the SDK. It talks to the small interface `SentrySdk` (`init`, `addBreadcrumb`, `captureException`), and the events are the JSON objects of the Sentry protocol, so replacing the SDK means writing one small class.

## How to turn it on

1. Add the SDK to `pubspec.yaml`, with its one-line justification, and add its package name (`sentry_flutter`) to `adapterPackages` in `tool/check_imports.dart`, so that only `lib/infrastructure` can import it.
2. Write the class that implements `SentrySdk` over the SDK, in `lib/infrastructure/monitoring/`. The scrubbing functions work on the JSON of the events, so the class converts at the edge:

   ```dart
   final class SentryFlutterSdk implements SentrySdk {
     @override
     void init(SentryOptions options) {
       // Sentry.init((o) {
       //   o.dsn = options.dsn;
       //   o.sendDefaultPii = options.sendDefaultPii;
       //   o.attachScreenshot = options.attachScreenshot;
       //   o.attachViewHierarchy = options.attachViewHierarchy;
       //   o.captureFailedRequests = options.enableCaptureFailedRequests;
       //   o.enableAutoPerformanceTracing = options.enableAutoPerformanceTracing;
       //   o.maxBreadcrumbs = options.maxBreadcrumbs;
       //   o.beforeBreadcrumb = (crumb, hint) => crumb == null ? null
       //       : Breadcrumb.fromJson(options.beforeBreadcrumb(crumb.toJson()) ?? {});
       //   o.beforeSend = (event, hint) =>
       //       SentryEvent.fromJson(options.beforeSend(event.toJson()));
       // });
     }
     // addBreadcrumb and captureException forward to Sentry.addBreadcrumb and
     // Sentry.captureException, with the level, tags, extra, fingerprint and user
     // of the context.
   }
   ```

   The comment is a sketch: it is not compiled in this repository, which has no Sentry dependency.
3. In the composition root (`lib/di`), read the address from the build (`--dart-define=SENTRY_DSN=...`, never from a file of the repository) and choose the adapter:

   ```dart
   final created = createSentryMonitoring(dsn, SentryFlutterSdk());
   final monitoring = switch (created) {
     Ok(:final value) => value,
     // An address that is not a DSN, or an SDK that cannot start: keep the console.
     Err() => const ConsoleMonitoring(),
   };
   ```

   `createSentryMonitoring` never throws: it answers `SentryStartFailure.invalidDsn` or `SentryStartFailure.sdkFailed`.
4. Check, with a test error sent from a debug build, that what arrives in Sentry holds nothing but the attributes of the port and the id of the user.
