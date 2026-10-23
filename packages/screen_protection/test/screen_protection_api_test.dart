import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_protection/screen_protection.dart';
import 'package:screen_protection/src/messages.g.dart' as messages;

const String _channelPrefix =
    'dev.flutter.pigeon.screen_protection.ScreenProtectionHostApi';
const String _eventsChannel =
    'dev.flutter.pigeon.screen_protection.ScreenProtectionEvents'
    '.streamCaptureEvents';
const MessageCodec<Object?> _codec = ScreenProtectionHostApi.pigeonChannelCodec;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;

  void answer(
    String method,
    Object? Function(List<Object?> arguments) handler,
  ) {
    messenger.setMockDecodedMessageHandler<Object?>(
      BasicMessageChannel<Object?>('$_channelPrefix.$method', _codec),
      (message) async =>
          handler(message is List<Object?> ? message : const <Object?>[]),
    );
  }

  final api = ScreenProtectionHostApi();

  test('asks the native side to turn the protection on and off', () async {
    final asked = <Object?>[];
    answer('setProtectionEnabled', (arguments) {
      asked.add(arguments.first);
      return <Object?>[null];
    });

    await api.setProtectionEnabled(true);
    await api.setProtectionEnabled(false);

    expect(asked, equals([true, false]));
  });

  test('fails with the error of the native side', () async {
    answer(
      'setProtectionEnabled',
      (_) => <Object?>['ERR_ACTIVITY', 'no activity', null],
    );

    await expectLater(
      api.setProtectionEnabled(true),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'ERR_ACTIVITY',
        ),
      ),
    );
  });

  test('reads whether the screen is captured', () async {
    answer('isCaptured', (_) => <Object?>[true]);

    expect(await api.isCaptured(), isTrue);
  });

  test('reads what the platform can do', () async {
    final capabilities = ProtectionCapabilities(
      protection: true,
      screenshotDetection: true,
      recordingDetection: false,
      secureView: false,
    );
    answer('capabilities', (_) => <Object?>[capabilities]);

    expect(await api.capabilities(), equals(capabilities));
  });

  test('receives the capture events of the native side, typed', () async {
    const channel = EventChannel(_eventsChannel, messages.pigeonMethodCodec);
    messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          events
            ..success(ScreenshotTakenMessage())
            ..success(CaptureChangedMessage(captured: true))
            ..endOfStream();
        },
      ),
    );

    final events = await streamCaptureEvents().toList();

    expect(events, [
      ScreenshotTakenMessage(),
      CaptureChangedMessage(captured: true),
    ]);
  });

  test('compares capture events by value', () {
    expect(
      CaptureChangedMessage(captured: true),
      equals(CaptureChangedMessage(captured: true)),
    );
    expect(
      CaptureChangedMessage(captured: true),
      isNot(equals(CaptureChangedMessage(captured: false))),
    );
  });
}
