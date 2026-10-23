import 'package:boardroom/features/documents/application/retryable_codes.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:test/test.dart';

void main() {
  group('the codes of the documents a second try can fix', () {
    test('are a screen protection that failed, and no other', () {
      expect([
        ...documentsRetryableCodes,
      ], equals([ScreenProtectionErrorCode.failed.value]));
    });

    test('leave out a platform that cannot protect a screen at all', () {
      expect(
        documentsRetryableCodes.contains(
          ScreenProtectionErrorCode.unsupported.value,
        ),
        isFalse,
      );
    });
  });
}
