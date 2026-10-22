import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/constants.dart';
import 'package:test/test.dart';

import '../support/builders.dart';
import '../support/matchers.dart';
import '../support/names.dart';

void main() {
  group('error codes', () {
    final families = {
      'validation': valuesOf(ValidationErrorCode.values),
      'authentication': valuesOf(AuthenticationErrorCode.values),
      'repository': valuesOf(RepositoryErrorCode.values),
      'voting': valuesOf(VotingErrorCode.values),
      'voteDelivery': valuesOf(VoteDeliveryErrorCode.values),
      'biometric': valuesOf(BiometricErrorCode.values),
      'storage': valuesOf(StorageErrorCode.values),
      'screenProtection': valuesOf(ScreenProtectionErrorCode.values),
    };

    test('are unique across every family, '
        'so that a union of errors is told apart by code alone', () {
      final all = families.values.expand((codes) => codes).toList();

      expect(all.toSet().length, equals(all.length));
    });
  });

  group('error factories', () {
    test('build a validation error with its field and rule', () {
      expect(
        validationError(ValidationField.email, ValidationRule.required),
        isAppError(ValidationErrorCode.validation.value, {
          'field': ValidationField.email,
          'rule': ValidationRule.required,
        }),
      );
    });

    test('build the authentication errors', () {
      expect(
        invalidCredentials().code,
        equals(AuthenticationErrorCode.invalidCredentials.value),
      );
      expect(
        sessionExpired().code,
        equals(AuthenticationErrorCode.sessionExpired.value),
      );
      expect(
        notAuthenticated().code,
        equals(AuthenticationErrorCode.notAuthenticated.value),
      );
      expect(
        sessionChanged().code,
        equals(AuthenticationErrorCode.sessionChanged.value),
      );
      expect(appLocked(), isAppError(AuthenticationErrorCode.appLocked.value));
    });

    test('build the repository errors', () {
      expect(
        networkUnavailable().code,
        equals(RepositoryErrorCode.networkUnavailable.value),
      );
      expect(notFound().code, equals(RepositoryErrorCode.notFound.value));
      expect(
        unauthorized().code,
        equals(RepositoryErrorCode.unauthorized.value),
      );
      expect(forbidden(), isAppError(RepositoryErrorCode.forbidden.value));
    });

    test('carry a technical cause only when one is given', () {
      expect(unexpected(), isAppError(RepositoryErrorCode.unexpected.value));
      expect(
        unexpected('HTTP 500'),
        isAppError(RepositoryErrorCode.unexpected.value, {'cause': 'HTTP 500'}),
      );
      expect(
        storageReadFailed(),
        isAppError(StorageErrorCode.readFailed.value),
      );
      expect(
        storageReadFailed('disk'),
        isAppError(StorageErrorCode.readFailed.value, {'cause': 'disk'}),
      );
      expect(
        storageWriteFailed(),
        isAppError(StorageErrorCode.writeFailed.value),
      );
      expect(
        storageWriteFailed('full'),
        isAppError(StorageErrorCode.writeFailed.value, {'cause': 'full'}),
      );
    });

    test('build the biometric errors', () {
      expect([
        biometricUnavailable().code,
        biometricNotEnrolled().code,
        biometricCancelled().code,
        biometricFailed().code,
        biometricLockedOut().code,
      ], equals(valuesOf(BiometricErrorCode.values)));
    });

    test('build the screen protection errors', () {
      expect([
        screenProtectionUnsupported().code,
        screenProtectionFailed().code,
      ], equals(valuesOf(ScreenProtectionErrorCode.values)));
    });
  });

  group('vote delivery errors', () {
    test('carry the structured data of the situation', () {
      expect(
        voteUndeliverable(5),
        isAppError(VoteDeliveryErrorCode.undeliverable.value, {'attempts': 5}),
      );
      expect(
        votePreviouslyRejected(voteUndeliverable(2)),
        isAppError(VoteDeliveryErrorCode.previouslyRejected.value, {
          'reason': voteUndeliverable(2),
        }),
      );
      expect(
        voteInProgress(),
        isAppError(VoteDeliveryErrorCode.inProgress.value),
      );
      expect(
        voteNotRejected(),
        isAppError(VoteDeliveryErrorCode.notRejected.value),
      );
    });

    test('are not business rejections of the server', () {
      expect(isVotingError(voteUndeliverable(1)), isFalse);
      expect(isVotingError(voteInProgress()), isFalse);
    });
  });

  group('isVotingError', () {
    final votingErrors = <VotingError>[
      ResolutionNotFoundError(resolutionId: aResolutionId()),
      const NotAParticipantError(),
      const NoVotingRightsError(),
      const ResolutionClosedError(),
      const VotingWindowOverError(),
      const AlreadyVotedError(source: AlreadyVotedSource.recorded),
    ];

    test('recognises every voting error', () {
      expect(
        votingErrors.map(isVotingError).toList(),
        equals(votingErrors.map((_) => true).toList()),
      );
      expect(votingErrors, hasLength(valuesOf(VotingErrorCode.values).length));
    });

    for (final error in <AppError>[
      networkUnavailable(),
      unauthorized(),
      forbidden(),
      appLocked(),
      unexpected(),
      biometricFailed(),
      storageReadFailed(),
    ]) {
      test('rejects the error ${formatPretty(error)} of another family', () {
        expect(isVotingError(error), isFalse);
      });
    }
  });
}
