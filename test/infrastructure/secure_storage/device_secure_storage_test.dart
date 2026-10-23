import 'package:boardroom/infrastructure/secure_storage/device_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// The native keychain cannot run in a test, so what stands in for it is the
// native side of the plugin: a handler on the channel the plugin talks to,
// which keeps the items in memory and remembers the options every call
// carried. The storage under test is the real one, with the plugin's own
// choice of options for each platform; the only things left to check in a
// wrapper this thin are that the values go through and which options it
// passes, for each of the three calls.

/// The channel of the plugin.
const MethodChannel _channel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// The names of the calls of the plugin and of their arguments.
const String _writeCall = 'write';
const String _readCall = 'read';
const String _deleteCall = 'delete';
const String _keyArgument = 'key';
const String _valueArgument = 'value';
const String _optionsArgument = 'options';

typedef _Call = ({String method, Map<String, String> options});

void main() {
  late Map<String, String> items;
  late List<_Call> calls;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    items = {};
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final arguments = (call.arguments as Map<Object?, Object?>)
              .cast<String, Object?>();
          calls.add((
            method: call.method,
            options: (arguments[_optionsArgument]! as Map<Object?, Object?>)
                .cast<String, String>(),
          ));
          final key = arguments[_keyArgument]! as String;
          switch (call.method) {
            case _writeCall:
              items[key] = arguments[_valueArgument]! as String;
              return null;
            case _readCall:
              return items[key];
            case _deleteCall:
              items.remove(key);
              return null;
          }
          throw MissingPluginException(call.method);
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('DeviceSecureStorage', () {
    test(
      'stores and reads a value, with the item kept on this device only',
      () async {
        const storage = DeviceSecureStorage();

        await storage.set('a.key', 'a value');

        expect(await storage.get('a.key'), equals('a value'));
        expect(
          deviceKeychain.iOptions.toMap(),
          containsPair(
            'accessibility',
            KeychainAccessibility.unlocked_this_device.name,
          ),
        );
        expect(
          deviceKeychain.mOptions.toMap(),
          containsPair(
            'accessibility',
            KeychainAccessibility.unlocked_this_device.name,
          ),
        );
        expect(
          deviceKeychain.iOptions.toMap(),
          containsPair('accountName', keychainService),
        );
      },
    );

    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      test('files every item of the app under the service of the app, '
          'readable on this device only, on ${platform.name}', () async {
        debugDefaultTargetPlatformOverride = platform;
        const storage = DeviceSecureStorage();

        await storage.set('a.key', 'a value');
        await storage.get('a.key');
        await storage.remove('a.key');

        expect(
          calls.map((call) => call.method),
          equals([_writeCall, _readCall, _deleteCall]),
        );
        for (final call in calls) {
          expect(
            call.options,
            allOf(
              containsPair('accountName', keychainService),
              containsPair(
                'accessibility',
                KeychainAccessibility.unlocked_this_device.name,
              ),
            ),
            reason: 'the options of ${call.method}',
          );
        }
      });
    }

    test('never lets the plugin delete what it cannot read on Android, '
        'with any of the three calls', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const storage = DeviceSecureStorage();

      await storage.set('a.key', 'a value');
      await storage.get('a.key');
      await storage.remove('a.key');

      expect(
        calls.map((call) => call.method),
        equals([_writeCall, _readCall, _deleteCall]),
      );
      for (final call in calls) {
        expect(
          call.options,
          containsPair('resetOnError', 'false'),
          reason: 'the options of ${call.method}',
        );
      }
      expect(
        deviceKeychain.aOptions.toMap(),
        containsPair('resetOnError', 'false'),
      );
    });

    test('reads a key that is not there as undefined', () async {
      expect(await const DeviceSecureStorage().get('missing'), isNull);
    });

    test('forgets a key, with the same options', () async {
      const storage = DeviceSecureStorage();
      await storage.set('a.key', 'a value');

      await storage.remove('a.key');

      expect(await storage.get('a.key'), isNull);
      expect(
        calls.map((call) => call.options),
        everyElement(equals(calls.first.options)),
      );
    });

    test('forgets a key that is not there without failing', () async {
      await expectLater(
        const DeviceSecureStorage().remove('missing'),
        completes,
      );
    });

    test('lets the error of a read through, so that a keychain that cannot '
        'be read is not taken for an empty one', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            throw PlatformException(code: 'keystore', message: 'unreadable');
          });

      await expectLater(
        const DeviceSecureStorage().get('a.key'),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
