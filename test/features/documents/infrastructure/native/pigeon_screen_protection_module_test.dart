import 'dart:async';

import 'package:boardroom/features/documents/infrastructure/native/pigeon_screen_protection_module.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_protection/screen_protection.dart';

/// A stand-in for the calls Pigeon generated: it records what Dart asked of the
/// native side, and answers like it.
final class _FakeHostApi extends ScreenProtectionHostApi {
  final List<bool> enabledCalls = [];
  bool captured = false;
  Object? failure;

  @override
  Future<void> setProtectionEnabled(bool enabled) async {
    enabledCalls.add(enabled);
    final error = failure;
    if (error != null) {
      throw error; // ignore: only_throw_errors, the test chooses the error.
    }
  }

  @override
  Future<bool> isCaptured() async => captured;

  @override
  Future<ProtectionCapabilities> capabilities() => throw UnimplementedError();
}

void main() {
  group(
    'PigeonScreenProtectionModule, over the typed channel of the plugin',
    () {
      late _FakeHostApi host;
      late StreamController<CaptureEventMessage> events;
      late PigeonScreenProtectionModule module;
      var streamsMade = 0;

      setUp(() {
        host = _FakeHostApi();
        events = StreamController<CaptureEventMessage>.broadcast();
        streamsMade = 0;
        module = PigeonScreenProtectionModule(
          host: host,
          events: () {
            streamsMade += 1;
            return events.stream;
          },
        );
      });

      tearDown(() => events.close());

      test(
        'turns the protection on and off through the generated call',
        () async {
          await module.setProtectionEnabled(enabled: true);
          await module.setProtectionEnabled(enabled: false);

          expect(host.enabledCalls, equals([true, false]));
        },
      );

      test('lets the failure of the native side reach the adapter', () async {
        host.failure = PlatformException(code: 'ERR_ACTIVITY');

        await expectLater(
          module.setProtectionEnabled(enabled: true),
          throwsA(isA<PlatformException>()),
        );
      });

      test('asks the native side whether the screen is captured', () async {
        host.captured = true;

        expect(await module.isCaptured(), isTrue);
      });

      test('hands the events of the stream to the listener, '
          'from one stream made once', () async {
        final heard = <CaptureEventMessage>[];
        final stop = module.addListener(heard.add, onError: (_) {});
        final second = module.addListener((_) {}, onError: (_) {});

        events
          ..add(ScreenshotTakenMessage())
          ..add(CaptureChangedMessage(captured: true));
        await Future<void>.delayed(Duration.zero);
        stop();
        second();
        events.add(ScreenshotTakenMessage());
        await Future<void>.delayed(Duration.zero);

        expect(
          heard,
          equals([
            ScreenshotTakenMessage(),
            CaptureChangedMessage(captured: true),
          ]),
        );
        expect(streamsMade, equals(1));
      });

      test('tells the failure of the stream to onError', () async {
        final errors = <Object>[];
        module.addListener((_) {}, onError: errors.add);

        events.addError(StateError('stream'));
        await Future<void>.delayed(Duration.zero);

        expect(errors, hasLength(1));
      });
    },
  );

  group('loadScreenProtectionModule', () {
    test('has a native side on Android and iOS', () {
      expect(
        loadScreenProtectionModule(platform: TargetPlatform.android),
        isA<PigeonScreenProtectionModule>(),
      );
      expect(
        loadScreenProtectionModule(platform: TargetPlatform.iOS),
        isA<PigeonScreenProtectionModule>(),
      );
    });

    test('has none where the plugin has no implementation', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(loadScreenProtectionModule(platform: platform), isNull);
      }
    });

    test('follows the platform of the app by default', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(loadScreenProtectionModule(), isNull);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(loadScreenProtectionModule(), isNotNull);
    });
  });
}
