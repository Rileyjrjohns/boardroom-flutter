import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/builders/matchers.dart';
import '../../../../support/builders/names.dart';

// The scenarios of `errors.test.ts` in React Native that are about the errors
// of `votes`. In Dart the families are in their feature, so their scenarios
// are here, with the same names (`tool/scenario_parity.dart` reads them for
// `errors.test.ts`: `splitScenarioFiles`).

void main() {
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
