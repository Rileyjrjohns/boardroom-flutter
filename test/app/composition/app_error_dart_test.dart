import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:test/test.dart';

import '../../support/builders/builders.dart';
import '../../support/builders/matchers.dart';

// Dart only: the TypeScript errors are object literals that jest compares
// field by field, the Dart ones are classes with their own equality, and the
// compiler checks that a switch over a sealed family is exhaustive. The root,
// `AppError`, is open (each feature declares its own families), and this is the
// one place that sees all of them, so it is here, in the tests of the
// composition, that every error is listed and that the families are told
// apart.

/// Every error of the domain: its stable code and its payload.
final List<(AppError, String, Map<String, Object?>)> _errors = [
  (
    const ValidationError(
      field: ValidationField.email,
      rule: ValidationRule.required,
    ),
    'validation',
    {'field': ValidationField.email, 'rule': ValidationRule.required},
  ),
  (const InvalidCredentialsError(), 'invalidCredentials', {}),
  (const SessionExpiredError(), 'sessionExpired', {}),
  (const NotAuthenticatedError(), 'notAuthenticated', {}),
  (const SessionChangedError(), 'sessionChanged', {}),
  (const AppLockedError(), 'appLocked', {}),
  (const NetworkUnavailableError(), 'networkUnavailable', {}),
  (const NotFoundError(), 'notFound', {}),
  (const UnauthorizedError(), 'unauthorized', {}),
  (const ForbiddenError(), 'forbidden', {}),
  (
    const UnexpectedError(cause: 'HTTP 500'),
    'unexpected',
    {'cause': 'HTTP 500'},
  ),
  (
    ResolutionNotFoundError(resolutionId: aResolutionId()),
    'resolutionNotFound',
    {'resolutionId': 'resolution-1'},
  ),
  (const NotAParticipantError(), 'notAParticipant', {}),
  (const NoVotingRightsError(), 'noVotingRights', {}),
  (const ResolutionClosedError(), 'resolutionClosed', {}),
  (const VotingWindowOverError(), 'votingWindowOver', {}),
  (
    const AlreadyVotedError(source: AlreadyVotedSource.queued),
    'alreadyVoted',
    {'source': AlreadyVotedSource.queued},
  ),
  (const BiometricUnavailableError(), 'biometricUnavailable', {}),
  (const BiometricNotEnrolledError(), 'biometricNotEnrolled', {}),
  (const BiometricCancelledError(), 'biometricCancelled', {}),
  (const BiometricFailedError(), 'biometricFailed', {}),
  (const BiometricLockedOutError(), 'biometricLockedOut', {}),
  (
    const StorageReadFailedError(cause: 'disk'),
    'storageReadFailed',
    {'cause': 'disk'},
  ),
  (const StorageWriteFailedError(), 'storageWriteFailed', {}),
  (const ScreenProtectionUnsupportedError(), 'screenProtectionUnsupported', {}),
  (const ScreenProtectionFailedError(), 'screenProtectionFailed', {}),
  (
    const VoteUndeliverableError(attempts: 5),
    'voteUndeliverable',
    {'attempts': 5},
  ),
  (
    const VotePreviouslyRejectedError(reason: ResolutionClosedError()),
    'votePreviouslyRejected',
    {'reason': const ResolutionClosedError()},
  ),
  (const VoteInProgressError(), 'voteInProgress', {}),
  (const VoteNotRejectedError(), 'voteNotRejected', {}),
];

/// The family of an error. `AppError` is open, so a `switch` over it cannot be
/// exhaustive and ends with a default; each sealed family has an exhaustive
/// `switch` of its own below.
String familyOf(AppError error) => switch (error) {
  ValidationError() => 'validation',
  AuthenticationError() => 'authentication',
  RepositoryError() => 'repository',
  BiometricError() => 'biometric',
  StorageError() => 'storage',
  ScreenProtectionError() => 'screenProtection',
  RejectionReason() => 'rejectionReason',
  VotePreviouslyRejectedError() ||
  VoteInProgressError() ||
  VoteNotRejectedError() => 'voteDelivery',
  _ => 'unknown',
};

/// The members of each sealed family, by an exhaustive switch: it stops
/// compiling when an error is added to the family and not handled here.
String authenticationKind(AuthenticationError error) => switch (error) {
  InvalidCredentialsError() => 'invalidCredentials',
  SessionExpiredError() => 'sessionExpired',
  NotAuthenticatedError() => 'notAuthenticated',
  SessionChangedError() => 'sessionChanged',
  AppLockedError() => 'appLocked',
};

String biometricKind(BiometricError error) => switch (error) {
  BiometricAvailabilityError() => 'availability',
  BiometricCancelledError() => 'cancelled',
  BiometricFailedError() => 'failed',
  BiometricLockedOutError() => 'lockedOut',
};

String screenProtectionKind(ScreenProtectionError error) => switch (error) {
  ScreenProtectionUnsupportedError() => 'unsupported',
  ScreenProtectionFailedError() => 'failed',
};

String storageKind(StorageError error) => switch (error) {
  StorageReadFailedError() => 'read',
  StorageWriteFailedError() => 'write',
};

String rejectionKind(RejectionReason reason) => switch (reason) {
  VotingError() => 'voting',
  VoteUndeliverableError() => 'undeliverable',
};

String votingKind(VotingError error) => switch (error) {
  ResolutionNotFoundError() => 'resolutionNotFound',
  NotAParticipantError() => 'notAParticipant',
  NoVotingRightsError() => 'noVotingRights',
  ResolutionClosedError() => 'resolutionClosed',
  VotingWindowOverError() => 'votingWindowOver',
  AlreadyVotedError() => 'alreadyVoted',
};

/// The same for the repository errors alone.
String repositoryKind(RepositoryError error) => switch (error) {
  GatewayError() => 'gateway',
  NotFoundError() => 'notFound',
  ForbiddenError() => 'forbidden',
};

void main() {
  group('the errors of the domain', () {
    for (final (error, code, payload) in _errors) {
      test('the error $code has its stable code and its payload', () {
        expect(error, isAppError(code, payload));
      });
    }

    test('are told apart by code alone: no two share one', () {
      final codes = [for (final (_, code, _) in _errors) code];

      expect(codes.toSet(), hasLength(codes.length));
    });

    test('belong to a family a switch can tell apart', () {
      expect(familyOf(const AppLockedError()), equals('authentication'));
      expect(familyOf(const NotFoundError()), equals('repository'));
      expect(familyOf(const BiometricFailedError()), equals('biometric'));
      expect(familyOf(const StorageWriteFailedError()), equals('storage'));
      expect(
        familyOf(const ScreenProtectionFailedError()),
        equals('screenProtection'),
      );
      expect(
        familyOf(const ResolutionClosedError()),
        equals('rejectionReason'),
      );
      expect(
        familyOf(const VoteUndeliverableError(attempts: 1)),
        equals('rejectionReason'),
      );
      expect(familyOf(const VoteInProgressError()), equals('voteDelivery'));
      expect(
        familyOf(
          const ValidationError(
            field: ValidationField.email,
            rule: ValidationRule.required,
          ),
        ),
        equals('validation'),
      );
      expect(authenticationKind(const AppLockedError()), equals('appLocked'));
      expect(biometricKind(const BiometricFailedError()), equals('failed'));
      expect(
        screenProtectionKind(const ScreenProtectionFailedError()),
        equals('failed'),
      );
      expect(storageKind(const StorageReadFailedError()), equals('read'));
      expect(
        rejectionKind(const VoteUndeliverableError(attempts: 1)),
        equals('undeliverable'),
      );
      expect(
        votingKind(const NotAParticipantError()),
        equals('notAParticipant'),
      );
      expect(
        repositoryKind(const NetworkUnavailableError()),
        equals('gateway'),
      );
      expect(repositoryKind(const UnexpectedError()), equals('gateway'));
      expect(repositoryKind(const ForbiddenError()), equals('forbidden'));
    });

    test('are equal when they have the same class and the same data', () {
      expect(unexpected('a'), equals(unexpected('a')));
      expect(unexpected('a').hashCode, equals(unexpected('a').hashCode));
      expect(unexpected(), equals(unexpected()));
      expect(unexpected('a'), isNot(equals(unexpected('b'))));
      expect(unexpected('a'), isNot(equals(unexpected())));
      expect(unauthorized(), isNot(equals(forbidden())));
      expect(storageReadFailed(), isNot(equals(storageWriteFailed())));
      expect(
        votePreviouslyRejected(voteUndeliverable(2)),
        equals(votePreviouslyRejected(voteUndeliverable(2))),
      );
      expect(
        votePreviouslyRejected(voteUndeliverable(2)),
        isNot(equals(votePreviouslyRejected(voteUndeliverable(3)))),
      );
    });

    test('print their code and their data', () {
      expect(notFound().toString(), equals('AppError(code: notFound)'));
      expect(
        unexpected('HTTP 500').toString(),
        equals('AppError(code: unexpected, cause: HTTP 500)'),
      );
      expect(
        validationError(
          ValidationField.email,
          ValidationRule.required,
        ).toString(),
        equals('AppError(code: validation, field: email, rule: required)'),
      );
    });
  });
}
