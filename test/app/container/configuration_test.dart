import 'package:boardroom/app/composition/settings.dart';
import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/app/container/container_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/builders/builders.dart';

// The scenarios of `configuration.test.ts`: the mock configuration is the
// development one, `EXPO_PUBLIC_BOARDROOM_ADAPTERS` is `BOARDROOM_ADAPTERS`.

const String _api = 'https://api.boardroom.example';

/// The settings of the environment, with the address of an API unless the test
/// says otherwise.
RawSettings _settings({
  String? adapters,
  String? apiBaseUrl = _api,
  bool? devStartsSignedIn,
  Object? requestTimeoutMillis,
  Object? allowDevicePasscode,
  String? sentryDsn,
}) => RawSettings(
  adapters: adapters,
  apiBaseUrl: apiBaseUrl,
  devStartsSignedIn: devStartsSignedIn,
  requestTimeoutMillis: requestTimeoutMillis,
  allowDevicePasscode: allowDevicePasscode,
  sentryDsn: sentryDsn,
);

Result<AppConfiguration, ContainerError> _parse(
  RawSettings settings, {
  bool development = true,
}) => parseConfiguration(settings, development: development);

Matcher _failsWith(String code, [Map<String, Object?> payload = const {}]) =>
    isA<Err<AppConfiguration, ContainerError>>().having(
      (result) => result.error,
      'error',
      isA<ContainerError>()
          .having((error) => error.code, 'code', code)
          .having((error) => error.payload, 'payload', equals(payload)),
    );

void main() {
  group('DevConfiguration', () {
    test('is the development configuration with the values of the '
        'configuration module', () {
      final configuration = DevConfiguration();

      expect(configuration.kind, equals(AdaptersKind.dev));
      expect(configuration.startSignedIn, equals(devStartsSignedIn));
      expect(configuration.latency, equals(devSimulatedLatency));
      expect(configuration.sessionLifetime, equals(devSessionLifetime));
    });

    test('starts signed out: the user signs in, as with the real '
        'adapters', () {
      expect(DevConfiguration().startSignedIn, isFalse);
    });
  });

  group('parseConfiguration, the adapters', () {
    for (final (name, raw) in [
      ('nothing is set', null),
      ('the define is empty', ''),
      ('the define is blank', '   '),
    ]) {
      test('defaults to the development configuration in a development build '
          'when $name', () {
        expect(
          _parse(_settings(adapters: raw)),
          equals(ok(DevConfiguration())),
        );
      });
    }

    for (final raw in ['dev', 'DEV', '  Dev \n']) {
      test('reads "$raw" as the development configuration', () {
        expect(
          _parse(_settings(adapters: raw)),
          equals(ok(DevConfiguration())),
        );
      });
    }

    test('starts the development configuration signed in when it is told to, '
        'and ignores the address of the API', () {
      expect(
        _parse(
          _settings(
            adapters: 'dev',
            apiBaseUrl: 'not even a url',
            devStartsSignedIn: true,
          ),
          development: false,
        ),
        equals(ok(DevConfiguration(startSignedIn: true))),
      );
    });

    for (final raw in ['http', 'HTTP', ' http ']) {
      test('reads "$raw" as the http configuration', () {
        expect(
          _parse(_settings(adapters: raw)),
          equals(
            ok(
              HttpConfiguration(
                baseUrl: _api,
                requestTimeout: httpRequestTimeout,
                allowDevicePasscode: allowDevicePasscodeFallback,
              ),
            ),
          ),
        );
      });
    }

    for (final raw in ['moc', 'dev,http', 'real', '0', 'null', 'mock']) {
      test('refuses "$raw" instead of falling back to the development '
          'configuration', () {
        expect(
          _parse(_settings(adapters: raw)),
          _failsWith('invalidAdaptersSetting', {'received': raw}),
        );
      });
    }

    test('reports what it found, trimmed', () {
      expect(
        _parse(_settings(adapters: '  staging ')),
        _failsWith('invalidAdaptersSetting', {'received': 'staging'}),
      );
    });

    group('outside of a development build', () {
      for (final (name, raw) in [
        ('nothing is set', null),
        ('the define is empty', ''),
        ('the define is blank', '   '),
      ]) {
        test('refuses to start on the development adapters when $name', () {
          expect(
            _parse(_settings(adapters: raw), development: false),
            _failsWith('missingAdaptersSetting'),
          );
        });
      }

      test('accepts the settings it knows, like a development build '
          'does', () {
        expect(
          _parse(_settings(adapters: 'dev'), development: false),
          isA<Ok<AppConfiguration, ContainerError>>(),
        );
        expect(
          _parse(_settings(adapters: 'http'), development: false),
          isA<Ok<AppConfiguration, ContainerError>>(),
        );
      });

      test('refuses a setting it does not know, like a development build '
          'does', () {
        expect(
          _parse(_settings(adapters: 'staging'), development: false),
          _failsWith('invalidAdaptersSetting', {'received': 'staging'}),
        );
      });
    });
  });

  group('parseConfiguration, the settings of the http adapters', () {
    Result<AppConfiguration, ContainerError> http({
      String? apiBaseUrl = _api,
      Object? requestTimeoutMillis,
      Object? allowDevicePasscode,
      bool development = true,
    }) => _parse(
      _settings(
        adapters: 'http',
        apiBaseUrl: apiBaseUrl,
        requestTimeoutMillis: requestTimeoutMillis,
        allowDevicePasscode: allowDevicePasscode,
      ),
      development: development,
    );

    test('normalises the address of the API', () {
      final result = http(apiBaseUrl: '  HTTPS://API.Boardroom.example/v1/  ');

      expect(
        result,
        isA<Ok<AppConfiguration, ContainerError>>().having(
          (ok) => (ok.value as HttpConfiguration).baseUrl,
          'baseUrl',
          'https://api.boardroom.example/v1',
        ),
      );
    });

    for (final (name, apiBaseUrl, code) in [
      ('nothing', null, 'missingApiBaseUrl'),
      ('a blank value', '  ', 'missingApiBaseUrl'),
      (
        'something that is not a URL',
        'api.boardroom.example',
        'invalidApiBaseUrl',
      ),
      (
        'a URL with a query',
        'https://api.boardroom.example?a=1',
        'invalidApiBaseUrl',
      ),
      (
        'a URL with credentials',
        'https://me:secret@api.boardroom.example',
        'invalidApiBaseUrl',
      ),
      ('another scheme', 'ftp://api.boardroom.example', 'invalidApiBaseUrl'),
    ]) {
      test('refuses $name for the address of the API, with a code of its '
          'own', () {
        expect(http(apiBaseUrl: apiBaseUrl), _failsWith(code));
      });
    }

    test('refuses http for a host that is not this machine outside of a '
        'development build', () {
      expect(
        http(apiBaseUrl: 'http://api.boardroom.example', development: false),
        _failsWith('insecureApiBaseUrl'),
      );
    });

    for (final apiBaseUrl in [
      'http://localhost:4000',
      'http://10.0.2.2:4000',
      'http://127.0.0.1:4000',
    ]) {
      test('accepts $apiBaseUrl outside of a development build: the traffic '
          'does not leave the machine', () {
        expect(
          http(apiBaseUrl: apiBaseUrl, development: false),
          isA<Ok<AppConfiguration, ContainerError>>(),
        );
      });
    }

    test('accepts http for any host in a development build, where the API '
        'runs on a computer of the network', () {
      expect(
        http(apiBaseUrl: 'http://192.168.1.20:4000'),
        isA<Ok<AppConfiguration, ContainerError>>(),
      );
    });

    test('takes the request timeout and the passcode fallback it is '
        'given', () {
      expect(
        http(requestTimeoutMillis: 5000, allowDevicePasscode: true),
        equals(
          ok(
            HttpConfiguration(
              baseUrl: _api,
              requestTimeout: aDuration(5000),
              allowDevicePasscode: true,
            ),
          ),
        ),
      );
    });

    for (final (name, value) in <(String, Object)>[
      ('below the minimum', minHttpRequestTimeout - 1),
      ('above the maximum', maxHttpRequestTimeout + 1),
      ('not a whole number', 2500.5),
      ('negative', -5),
      ('not a number', '5000'),
      ('not finite', double.infinity),
      ('not a number at all', double.nan),
      ('zero', 0),
    ]) {
      test('refuses a request timeout that is $name', () {
        expect(
          http(requestTimeoutMillis: value),
          _failsWith('invalidRequestTimeout'),
        );
      });
    }

    for (final millis in [minHttpRequestTimeout, maxHttpRequestTimeout]) {
      test('accepts the bounds of the request timeout: $millis', () {
        expect(
          http(requestTimeoutMillis: millis),
          isA<Ok<AppConfiguration, ContainerError>>(),
        );
      });
    }

    for (final value in <Object>['yes', 1]) {
      test('refuses $value for the passcode fallback, which is a yes or a '
          'no', () {
        expect(
          http(allowDevicePasscode: value),
          _failsWith('invalidBiometricFallback'),
        );
      });
    }

    test('checks the address before the other settings', () {
      expect(
        http(
          apiBaseUrl: null,
          requestTimeoutMillis: 1,
          allowDevicePasscode: 'x',
        ),
        _failsWith('missingApiBaseUrl'),
      );
    });
  });

  group('the address of the crash reporter', () {
    const dsn = 'https://0123456789abcdef@o123456.ingest.sentry.io/4500000000';

    test('is left out when there is none, so that nothing changes for a '
        'build without one', () {
      for (final raw in <String?>[null, '', '   ']) {
        final result = _parse(_settings(adapters: 'dev', sentryDsn: raw));

        expect(
          result,
          isA<Ok<AppConfiguration, ContainerError>>().having(
            (ok) => ok.value.sentryDsn,
            'sentryDsn',
            isNull,
          ),
        );
      }
    });

    for (final adapters in ['dev', 'http']) {
      test('is kept, trimmed, with the $adapters adapters', () {
        final result = _parse(
          _settings(adapters: adapters, sentryDsn: '  $dsn  '),
        );

        expect(
          result,
          isA<Ok<AppConfiguration, ContainerError>>().having(
            (ok) => ok.value.sentryDsn,
            'sentryDsn',
            dsn,
          ),
        );
      });
    }

    test('does not make a bad address a reason not to start', () {
      expect(
        _parse(_settings(adapters: 'dev', sentryDsn: 'not an address')),
        isA<Ok<AppConfiguration, ContainerError>>(),
      );
    });
  });

  group('RawSettings.fromEnvironment', () {
    test('reads nothing from a build without defines: every setting is '
        'blank', () {
      const settings = RawSettings.fromEnvironment();

      expect(settings.adapters, isEmpty);
      expect(settings.apiBaseUrl, isEmpty);
      expect(settings.sentryDsn, isEmpty);
      expect(settings.devStartsSignedIn, isNull);
      expect(settings.requestTimeoutMillis, isNull);
      expect(settings.allowDevicePasscode, isNull);
    });

    test('names the defines the way the documents do', () {
      expect(RawSettings.adaptersDefine, equals('BOARDROOM_ADAPTERS'));
      expect(RawSettings.apiBaseUrlDefine, equals('BOARDROOM_API_BASE_URL'));
      expect(RawSettings.sentryDsnDefine, equals('BOARDROOM_SENTRY_DSN'));
    });
  });
}
