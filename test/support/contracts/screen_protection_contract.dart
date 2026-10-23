import 'dart:async';

import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:test/test.dart';

/// What the suite needs besides the port.
final class ScreenProtectionHarness {
  /// Creates a harness.
  const new({
    required this.protection,
    required this.isEnabled,
    required this.emit,
  });

  /// The adapter under test.
  final ScreenProtection protection;

  /// Whether the protection is on, as far as the adapter can tell.
  final bool Function() isEnabled;

  /// Simulates the system reporting a capture.
  final void Function(ScreenCaptureEvent event) emit;
}

/// Makes a harness, now or later.
typedef ScreenProtectionFactory = FutureOr<ScreenProtectionHarness> Function();

const _screenshot = ScreenCaptureEvent(kind: ScreenCaptureKind.screenshotTaken);
const _recording = ScreenCaptureEvent(kind: ScreenCaptureKind.recordingStarted);

/// The contract of `ScreenProtection`, as a suite any implementation runs: one
/// global switch, idempotent in both directions, and capture events delivered
/// to every subscriber until it unsubscribes, which can be done twice. The
/// factory returns a protection that is off and has no subscriber, on a
/// platform that supports it.
void describeScreenProtectionContract(
  String name,
  ScreenProtectionFactory createHarness,
) {
  group('$name honours the ScreenProtection contract', () {
    late ScreenProtectionHarness harness;
    late ScreenProtection protection;

    setUp(() async {
      harness = await createHarness();
      protection = harness.protection;
    });

    test('turns on and off', () async {
      expect(harness.isEnabled(), isFalse);

      expect(await protection.enable(), equals(ok<void>(null)));
      expect(harness.isEnabled(), isTrue);

      expect(await protection.disable(), equals(ok<void>(null)));
      expect(harness.isEnabled(), isFalse);
    });

    test('is idempotent: enabling twice leaves it on, '
        'and disabling twice, or when it is off, succeeds', () async {
      expect(await protection.disable(), equals(ok<void>(null)));

      await protection.enable();
      expect(await protection.enable(), equals(ok<void>(null)));
      expect(harness.isEnabled(), isTrue);

      await protection.disable();
      expect(await protection.disable(), equals(ok<void>(null)));
      expect(harness.isEnabled(), isFalse);
    });

    test('applies the calls in the order they were issued, '
        'whether or not each one is awaited', () async {
      final first = protection.enable();
      final second = protection.disable();
      await Future.wait([first, second]);
      expect(harness.isEnabled(), isFalse);

      final third = protection.disable();
      final fourth = protection.enable();
      await Future.wait([third, fourth]);
      expect(harness.isEnabled(), isTrue);
    });

    test('has taken effect when enable resolves', () async {
      await protection.enable();

      expect(harness.isEnabled(), isTrue);
    });

    test('is one global switch: a single disable turns it off '
        'however often it was enabled', () async {
      await protection.enable();
      await protection.enable();

      await protection.disable();

      expect(harness.isEnabled(), isFalse);
    });

    test('delivers capture events to a subscriber, in order, '
        'until it unsubscribes', () {
      final received = <ScreenCaptureEvent>[];
      final unsubscribe = protection.subscribe(received.add);

      harness
        ..emit(_screenshot)
        ..emit(_recording);
      unsubscribe();
      harness.emit(_screenshot);

      expect(received, equals([_screenshot, _recording]));
    });

    test('delivers an event to every subscriber, '
        'and stops each one on its own', () {
      final first = <ScreenCaptureEvent>[];
      final second = <ScreenCaptureEvent>[];
      final stopFirst = protection.subscribe(first.add);
      protection.subscribe(second.add);

      harness.emit(_screenshot);
      stopFirst();
      harness.emit(_recording);

      expect(first, equals([_screenshot]));
      expect(second, equals([_screenshot, _recording]));
    });

    test('lets a subscriber unsubscribe twice without harm to the others', () {
      final kept = <ScreenCaptureEvent>[];
      final stop = protection.subscribe((_) {});
      protection.subscribe(kept.add);

      stop();
      stop();
      harness.emit(_screenshot);

      expect(kept, equals([_screenshot]));
    });

    test('reports a capture to nobody when nobody subscribed', () {
      expect(() => harness.emit(_screenshot), returnsNormally);
    });
  });
}
