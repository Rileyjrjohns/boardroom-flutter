import 'package:boardroom/app/composition/retryable_codes.dart';
import 'package:boardroom/core/application/retryable_codes.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/features/documents/application/retryable_codes.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:test/test.dart';

// Dart only: the core knows no feature, so the codes a second try can fix are
// declared by the core and by each feature, and the composition puts them
// together (see docs/architecture.md).

void main() {
  group('the retryable codes, assembled by the composition', () {
    test(
      'are the ones the core declares and the ones the documents declare',
      () {
        expect(
          retryableCodes,
          equals({...coreRetryableCodes, ...documentsRetryableCodes}),
        );
      },
    );

    test('are the four codes they have always been', () {
      expect(
        retryableCodes,
        equals({
          RepositoryErrorCode.networkUnavailable.value,
          RepositoryErrorCode.unexpected.value,
          StorageErrorCode.readFailed.value,
          ScreenProtectionErrorCode.failed.value,
        }),
      );
    });

    test(
      'are what the core declares: the network, the server and the store',
      () {
        expect(
          coreRetryableCodes,
          equals({
            RepositoryErrorCode.networkUnavailable.value,
            RepositoryErrorCode.unexpected.value,
            StorageErrorCode.readFailed.value,
          }),
        );
      },
    );

    test('are what the documents declare: a screen protection that failed', () {
      expect(
        documentsRetryableCodes,
        equals({ScreenProtectionErrorCode.failed.value}),
      );
    });

    test('cannot be changed once assembled', () {
      expect(() => retryableCodes.add('x'), throwsUnsupportedError);
      expect(() => coreRetryableCodes.add('x'), throwsUnsupportedError);
      expect(() => documentsRetryableCodes.add('x'), throwsUnsupportedError);
    });
  });
}
