import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/features/documents/infrastructure/in_memory_screen_protection.dart';
import 'package:test/test.dart';

import '../../../support/contracts/screen_protection_contract.dart';

void main() {
  describeScreenProtectionContract('InMemoryScreenProtection', () {
    final protection = InMemoryScreenProtection();
    return ScreenProtectionHarness(
      protection: protection,
      isEnabled: protection.isEnabled,
      emit: protection.emit,
    );
  });

  group('InMemoryScreenProtection, configured for a test', () {
    test('fails to enable while told to, and stays off', () async {
      final protection = InMemoryScreenProtection()
        ..failEnableWith(screenProtectionUnsupported());

      expect(
        await protection.enable(),
        equals(err(screenProtectionUnsupported())),
      );
      expect(protection.isEnabled(), isFalse);

      protection.failEnableWith(null);
      expect(await protection.enable(), equals(ok<void>(null)));
      expect(protection.isEnabled(), isTrue);
    });

    test('fails to disable while told to, and stays on', () async {
      final protection = InMemoryScreenProtection();
      await protection.enable();
      protection.failDisableWith(screenProtectionFailed());

      expect(await protection.disable(), equals(err(screenProtectionFailed())));
      expect(protection.isEnabled(), isTrue);

      protection.failDisableWith(null);
      expect(await protection.disable(), equals(ok<void>(null)));
      expect(protection.isEnabled(), isFalse);
    });

    test('reports a capture to the subscribers', () {
      final protection = InMemoryScreenProtection();
      final received = <ScreenCaptureKind>[];
      protection
        ..subscribe((event) => received.add(event.kind))
        ..emit(
          const ScreenCaptureEvent(kind: ScreenCaptureKind.recordingStarted),
        );

      expect(received, equals([ScreenCaptureKind.recordingStarted]));
    });
  });
}
