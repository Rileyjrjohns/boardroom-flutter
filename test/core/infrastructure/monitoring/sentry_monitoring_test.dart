import 'dart:convert';

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/monitoring/sentry_monitoring.dart';
import 'package:test/test.dart';

// The real SDK needs its native module and sends what it is given over the
// network, and the project has none. This wrapper is tested against a stand-in
// that records the three calls it makes; `scrubEvent` and its relatives are
// plain functions, tested as such.

typedef _Exception = ({ReportedError exception, SentryJson context});

final class _RecordingSdk implements SentrySdk {
  new({
    this.failOnBreadcrumb = false,
    this.failOnException = false,
    this.failOnInit = false,
  });

  final bool failOnBreadcrumb;
  final bool failOnException;
  final bool failOnInit;
  final List<SentryOptions> inits = [];
  final List<SentryJson> breadcrumbs = [];
  final List<_Exception> exceptions = [];

  @override
  void init(SentryOptions options) {
    if (failOnInit) {
      throw StateError('native module missing');
    }
    inits.add(options);
  }

  @override
  void addBreadcrumb(SentryJson breadcrumb) {
    if (failOnBreadcrumb) {
      throw StateError('sdk down');
    }
    breadcrumbs.add(breadcrumb);
  }

  @override
  void captureException(ReportedError exception, SentryJson context) {
    if (failOnException) {
      throw StateError('sdk down');
    }
    exceptions.add((exception: exception, context: context));
  }
}

const String _dsn =
    'https://0123456789abcdef@o123456.ingest.sentry.io/4500000000';

void main() {
  group('SentryMonitoring', () {
    test('turns a log into a breadcrumb with the level of the port, '
        'the event and the allowed data', () {
      final sdk = _RecordingSdk();

      SentryMonitoring(sdk).log(
        LogLevel.warn,
        MonitoringEvent.cacheEntryDiscarded,
        {LogAttribute.meetingId: 'meeting-1', LogAttribute.attempts: 2},
      );

      expect(
        sdk.breadcrumbs,
        equals([
          {
            'category': breadcrumbCategory,
            'message': MonitoringEvent.cacheEntryDiscarded.value,
            'level': 'warning',
            'data': {'meetingId': 'meeting-1', 'attempts': 2},
          },
        ]),
      );
    });

    test('logs an event with no attributes as a breadcrumb with no data', () {
      final sdk = _RecordingSdk();

      SentryMonitoring(sdk).log(LogLevel.info, MonitoringEvent.voteQueued);

      expect(sdk.breadcrumbs, hasLength(1));
      expect(sdk.breadcrumbs.single['level'], equals('info'));
      expect(sdk.breadcrumbs.single['data'], equals({}));
    });

    test('reports a captured error as an exception named by its code, '
        'tagged with the code and the event', () {
      final sdk = _RecordingSdk();

      SentryMonitoring(sdk).captureError(
        MonitoringEvent.cacheWriteFailed,
        storageWriteFailed('disk full'),
        {LogAttribute.resource: 'meeting'},
      );

      final reported = sdk.exceptions.single;
      expect(reported.exception.name, equals('storageWriteFailed'));
      expect(
        reported.exception.message,
        equals('${MonitoringEvent.cacheWriteFailed.value}: disk full'),
      );
      expect(
        reported.context,
        equals({
          'level': 'error',
          'tags': {
            SentryTag.event: MonitoringEvent.cacheWriteFailed.value,
            SentryTag.errorCode: 'storageWriteFailed',
          },
          'extra': {'resource': 'meeting'},
          'fingerprint': [
            MonitoringEvent.cacheWriteFailed.value,
            'storageWriteFailed',
          ],
        }),
      );
    });

    test(
      'names the exception by the event alone when the error has no cause',
      () {
        final sdk = _RecordingSdk();

        SentryMonitoring(
          sdk,
        ).captureError(MonitoringEvent.cachePurgeFailed, storageWriteFailed());

        expect(
          sdk.exceptions.single.exception.message,
          equals(MonitoringEvent.cachePurgeFailed.value),
        );
      },
    );

    test('knows the user by the id the port passes, and by nothing else', () {
      final sdk = _RecordingSdk();

      SentryMonitoring(sdk).captureError(
        MonitoringEvent.signOutFailed,
        storageWriteFailed(),
        {LogAttribute.userId: 'user-1'},
      );

      expect(sdk.exceptions.single.context['user'], equals({'id': 'user-1'}));
    });

    test('leaves out the user when the port passes none', () {
      final sdk = _RecordingSdk();

      SentryMonitoring(sdk)
          .captureError(MonitoringEvent.signOutFailed, storageWriteFailed());

      expect(sdk.exceptions.single.context.containsKey('user'), isFalse);
    });

    test(
      'drops an attribute that is not one of the port, even when it is passed',
      () {
        final sdk = _RecordingSdk();
        // A call site cannot write this (the type forbids it); a value the
        // attributes cannot hold stands for a bug that does.
        final sneaky = <LogAttribute, Object>{
          LogAttribute.resource: 'meeting',
          LogAttribute.reason: <String, Object?>{'email': 'ada@example.com'},
        };

        SentryMonitoring(sdk)
          ..log(LogLevel.info, MonitoringEvent.voteQueued, sneaky)
          ..captureError(
            MonitoringEvent.cacheReadFailed,
            storageWriteFailed(),
            sneaky,
          );

        expect(
          jsonEncode([
            sdk.breadcrumbs,
            sdk.exceptions.map((e) => e.context).toList(),
          ]),
          isNot(contains('ada@example.com')),
        );
        expect(sdk.breadcrumbs.single['data'], equals({'resource': 'meeting'}));
      },
    );

    test('never throws, whatever the SDK does', () {
      final monitoring = SentryMonitoring(
        _RecordingSdk(failOnBreadcrumb: true, failOnException: true),
      );

      expect(
        () => monitoring.log(LogLevel.info, MonitoringEvent.voteQueued),
        returnsNormally,
      );
      expect(
        () => monitoring.captureError(
          MonitoringEvent.cacheReadFailed,
          storageWriteFailed(),
        ),
        returnsNormally,
      );
    });
  });

  group('allowedAttributes', () {
    test('keeps the attribute names of the port with a string, a '
        'number or a boolean', () {
      expect(
        allowedAttributes({
          'userId': 'user-1',
          'attempts': 3,
          'synced': true,
          'email': 'ada@example.com',
          'meetingId': {'nested': 'object'},
          'resource': null,
        }),
        equals({'userId': 'user-1', 'attempts': 3, 'synced': true}),
      );
    });

    test('cuts a long text, and accepts no data at all', () {
      expect(
        allowedAttributes({'issuePaths': 'x' * 500})['issuePaths'],
        hasLength(200),
      );
      expect(allowedAttributes(null), equals({}));
    });
  });

  group('keepOwnBreadcrumb', () {
    test('keeps the breadcrumbs of the app, with the allowed data only', () {
      expect(
        keepOwnBreadcrumb({
          'category': breadcrumbCategory,
          'message': MonitoringEvent.voteQueued.value,
          'data': {
            'resolutionId': 'r-1',
            'url': 'https://api.example.com/votes/secret',
          },
        }),
        equals({
          'category': breadcrumbCategory,
          'message': MonitoringEvent.voteQueued.value,
          'data': {'resolutionId': 'r-1'},
        }),
      );
    });

    for (final category in [
      'console',
      'xhr',
      'fetch',
      'navigation',
      'ui.click',
    ]) {
      test('drops the automatic $category breadcrumb of the SDK', () {
        expect(
          keepOwnBreadcrumb({
            'category': category,
            'message': 'GET https://api.example.com/me',
          }),
          isNull,
        );
      });
    }
  });

  group('scrubEvent', () {
    final crash = <String, Object?>{
      'event_id': 'abc',
      'level': 'fatal',
      'message': 'Cannot read email of ada@example.com',
      'request': {
        'url': 'https://api.example.com/meetings/m-1?token=secret',
        'cookies': {'sid': 'x'},
      },
      'server_name': 'Ada’s iPhone',
      'modules': {'left': '1.0.0'},
      'user': {
        'id': 'user-1',
        'email': 'ada@example.com',
        'username': 'ada',
        'ip_address': '10.0.0.7',
      },
      'tags': {
        'event': MonitoringEvent.cacheWriteFailed.value,
        'resource': 'meeting',
        'note': 'ada@example.com',
      },
      'extra': {
        'meetingId': 'm-1',
        'title': 'Board meeting of the merger',
        'attempts': 2,
      },
      'contexts': {
        'device': {
          'model': 'Pixel 9',
          'name': 'Ada’s Pixel',
          'simulator': false,
        },
        'os': {'name': 'Android', 'version': '16'},
        'document': {'text': 'confidential'},
      },
      'breadcrumbs': [
        {
          'category': 'fetch',
          'data': {'url': 'https://api.example.com/documents/d-1'},
        },
        {'category': 'console', 'message': 'user ada@example.com signed in'},
        {
          'category': breadcrumbCategory,
          'message': 'voteQueued',
          'data': {'resolutionId': 'r-1', 'who': 'ada'},
        },
      ],
      'exception': {
        'values': [
          {
            'type': 'storageWriteFailed',
            'value': 'cacheWriteFailed: disk full',
          },
        ],
      },
    };

    test('keeps nothing that is not an allowed attribute', () {
      final scrubbed = scrubEvent(crash);

      expect(
        scrubbed['tags'],
        equals({
          'event': MonitoringEvent.cacheWriteFailed.value,
          'resource': 'meeting',
        }),
      );
      expect(scrubbed['extra'], equals({'meetingId': 'm-1', 'attempts': 2}));
      expect(
        scrubbed['breadcrumbs'],
        equals([
          {
            'category': breadcrumbCategory,
            'message': 'voteQueued',
            'data': {'resolutionId': 'r-1'},
          },
        ]),
      );
    });

    test('keeps the id of the user and no other field of it', () {
      expect(scrubEvent(crash)['user'], equals({'id': 'user-1'}));
      expect(
        scrubEvent({
          ...crash,
          'user': {'email': 'ada@example.com'},
        }).containsKey('user'),
        isFalse,
      );
      expect(scrubEvent({}).containsKey('user'), isFalse);
    });

    test('removes the request, the server name and the modules', () {
      final scrubbed = scrubEvent(crash);

      expect(scrubbed.containsKey('request'), isFalse);
      expect(scrubbed.containsKey('server_name'), isFalse);
      expect(scrubbed.containsKey('modules'), isFalse);
    });

    test(
      'keeps the technical contexts, field by field, and drops the others',
      () {
        expect(
          scrubEvent(crash)['contexts'],
          equals({
            'device': {'model': 'Pixel 9', 'simulator': false},
            'os': {'name': 'Android', 'version': '16'},
          }),
        );
      },
    );

    test(
      'keeps the whole trace context, which holds random ids and nothing else',
      () {
        expect(
          scrubEvent({
            ...crash,
            'contexts': {
              'trace': {'trace_id': 't', 'span_id': 's'},
            },
          })['contexts'],
          equals({
            'trace': {'trace_id': 't', 'span_id': 's'},
          }),
        );
      },
    );

    test('keeps the message of an error the app reported, '
        'and drops the one of an error it did not', () {
      expect(
        (scrubEvent(crash)['exception']! as Map<String, Object?>)['values'],
        equals([
          {
            'type': 'storageWriteFailed',
            'value': 'cacheWriteFailed: disk full',
          },
        ]),
      );

      final uncaught = scrubEvent({
        ...crash,
        'tags': <String, Object?>{},
        'exception': {
          'values': [
            {'type': 'TypeError', 'value': "Cannot read 'email' of Ada"},
          ],
        },
      });
      expect(
        (uncaught['exception']! as Map<String, Object?>)['values'],
        equals([
          {'type': 'TypeError'},
        ]),
      );
      expect(uncaught.containsKey('message'), isFalse);
    });

    test(
      'leaves nothing of the personal data of the event in what it returns',
      () {
        final serialised = jsonEncode(scrubEvent(crash));

        for (final secret in [
          'ada@example.com',
          'Ada',
          'token=secret',
          '10.0.0.7',
          'merger',
          'confidential',
        ]) {
          expect(serialised, isNot(contains(secret)));
        }
      },
    );

    test('copes with an event that has none of the optional parts', () {
      expect(
        scrubEvent({}),
        equals({
          'tags': <String, Object?>{},
          'extra': <String, Object?>{},
          'contexts': <String, Object?>{},
          'breadcrumbs': <Object?>[],
        }),
      );
    });
  });

  group('isSentryDsn', () {
    for (final dsn in [
      _dsn,
      'https://abc@sentry.example.com:9000/relay/12',
      'https://abc:def@o1.ingest.de.sentry.io/1',
    ]) {
      test('accepts $dsn', () {
        expect(isSentryDsn(dsn), isTrue);
      });
    }

    for (final dsn in [
      '',
      'not a url',
      'http://abc@o1.ingest.sentry.io/1',
      'https://o1.ingest.sentry.io/1',
      'https://abc@o1.ingest.sentry.io/',
      'https://abc@o1.ingest.sentry.io/project',
      'https://abc@o1.ingest.sentry.io/1 extra',
    ]) {
      test('refuses "$dsn"', () {
        expect(isSentryDsn(dsn), isFalse);
      });
    }
  });

  group('sentryOptions', () {
    test('starts with the address, no default personal data, '
        'no screenshot and the scrubbing hooks', () {
      final options = sentryOptions(_dsn);

      expect(options.dsn, equals(_dsn));
      expect(options.sendDefaultPii, isFalse);
      expect(options.attachScreenshot, isFalse);
      expect(options.attachViewHierarchy, isFalse);
      expect(options.enableCaptureFailedRequests, isFalse);
      expect(options.enableAutoPerformanceTracing, isFalse);
      expect(options.beforeSend, same(scrubEvent));
      expect(options.beforeBreadcrumb, same(keepOwnBreadcrumb));
    });
  });

  group('createSentryMonitoring', () {
    test(
      'starts the SDK with the options and answers the monitoring over it',
      () {
        final sdk = _RecordingSdk();

        final created = createSentryMonitoring(_dsn, sdk);

        expect(sdk.inits, hasLength(1));
        expect(sdk.inits.single.dsn, equals(_dsn));
        expect(created, isA<Ok<Monitoring, SentryStartFailure>>());
        expect(
          (created as Ok<Monitoring, SentryStartFailure>).value,
          isA<SentryMonitoring>(),
        );
      },
    );

    test('refuses an address that is not a DSN, without starting the SDK', () {
      final sdk = _RecordingSdk();

      expect(
        createSentryMonitoring('nonsense', sdk),
        equals(err(SentryStartFailure.invalidDsn)),
      );
      expect(sdk.inits, isEmpty);
    });

    test(
      'answers a failure, and does not throw, when the SDK cannot start',
      () {
        expect(
          createSentryMonitoring(_dsn, _RecordingSdk(failOnInit: true)),
          equals(err(SentryStartFailure.sdkFailed)),
        );
      },
    );
  });
}
