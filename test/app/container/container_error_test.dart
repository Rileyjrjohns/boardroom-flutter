import 'package:boardroom/app/container/container_error.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/infrastructure/persistence/protected_database.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the container errors', () {
    test('have the codes of the specification, to the letter', () {
      expect(
        valuesOf(ContainerErrorCode.values),
        equals([
          'invalidAdaptersSetting',
          'missingAdaptersSetting',
          'missingApiBaseUrl',
          'invalidApiBaseUrl',
          'insecureApiBaseUrl',
          'invalidRequestTimeout',
          'invalidBiometricFallback',
          'storageUnavailable',
          'platformUnavailable',
          'mockDataInvalid',
        ]),
      );
    });

    test('carry their data in the payload, and are equal by value', () {
      expect(invalidAdaptersSetting('x').payload, {'received': 'x'});
      expect(mockDataInvalid('seed').payload, {'detail': 'seed'});
      expect(storageUnavailable(DatabaseFailureReason.open).payload, {
        'reason': DatabaseFailureReason.open,
      });
      expect(missingApiBaseUrl().payload, isEmpty);
      expect(invalidApiBaseUrl(), equals(invalidApiBaseUrl()));
      expect(mockDataInvalid('a'), isNot(equals(mockDataInvalid('b'))));
    });

    test('are told apart from every other family by code alone', () {
      final others = [
        ...valuesOf(ValidationErrorCode.values),
        ...valuesOf(AuthenticationErrorCode.values),
        ...valuesOf(RepositoryErrorCode.values),
        ...valuesOf(VotingErrorCode.values),
        ...valuesOf(VoteDeliveryErrorCode.values),
        ...valuesOf(BiometricErrorCode.values),
        ...valuesOf(StorageErrorCode.values),
        ...valuesOf(ScreenProtectionErrorCode.values),
      ];
      final ours = valuesOf(ContainerErrorCode.values);

      expect(others.toSet().intersection(ours.toSet()), isEmpty);
      expect(ours.toSet(), hasLength(ours.length));
      expect(ours, isNot(contains(startupAbortedCode)));
    });

    test('name the abandoned start with a code of their own', () {
      expect(startupAbortedCode, equals('startupAborted'));
    });
  });
}
