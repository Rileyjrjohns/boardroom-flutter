// The arguments restate the values of the scenario, even when they are the
// defaults of the builders.
// ignore_for_file: avoid_redundant_argument_values

import 'package:boardroom/domain/entities/document.dart';
import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/domain/entities/participant.dart';
import 'package:boardroom/domain/entities/resolution.dart';
import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/constants.dart';
import 'package:boardroom/domain/value_objects/meeting_period.dart';
import 'package:boardroom/domain/value_objects/page_request.dart';
import 'package:boardroom/domain/value_objects/vote_choice.dart';
import 'package:test/test.dart';

import 'support/builders.dart';

// The tests of the other files compare a constant with itself, which no change
// of its value could break. These pin the values themselves: they are stored
// (in SQLite, in the query cache), sent to the server, and mapped to
// translation keys, so changing one is a decision, not an accident.

/// The members of an enumeration by name, with their stable strings: the
/// counterpart of the `as const` object of the React Native code, whose keys
/// are the members.
Map<String, String> _pinned(Iterable<StableValue> members) => {
  for (final member in members) (member as Enum).name: member.value,
};

void main() {
  group('the values that are stored and mapped to translations', () {
    test('are those of the vote choices, the roles, the levels '
        'and the statuses', () {
      expect(
        _pinned(VoteChoice.values),
        equals({
          'forChoice': 'for',
          'against': 'against',
          'abstain': 'abstain',
        }),
      );
      expect(
        _pinned(MeetingPeriod.values),
        equals({'upcoming': 'upcoming', 'past': 'past'}),
      );
      expect(
        _pinned(ParticipantRole.values),
        equals({
          'chair': 'chair',
          'secretary': 'secretary',
          'member': 'member',
          'guest': 'guest',
        }),
      );
      expect(
        _pinned(ConfidentialityLevel.values),
        equals({
          'public': 'public',
          'internal': 'internal',
          'confidential': 'confidential',
        }),
      );
      expect(
        _pinned(ResolutionStatus.values),
        equals({'open': 'open', 'closed': 'closed'}),
      );
      expect(
        _pinned(OutboxStatus.values),
        equals({'pending': 'pending', 'rejected': 'rejected'}),
      );
    });

    test('are those of the error codes', () {
      expect(
        _pinned(ValidationErrorCode.values),
        equals({'validation': 'validation'}),
      );
      expect(
        _pinned(AuthenticationErrorCode.values),
        equals({
          'invalidCredentials': 'invalidCredentials',
          'sessionExpired': 'sessionExpired',
          'notAuthenticated': 'notAuthenticated',
          'sessionChanged': 'sessionChanged',
          'appLocked': 'appLocked',
        }),
      );
      expect(
        _pinned(RepositoryErrorCode.values),
        equals({
          'networkUnavailable': 'networkUnavailable',
          'notFound': 'notFound',
          'unauthorized': 'unauthorized',
          'forbidden': 'forbidden',
          'unexpected': 'unexpected',
        }),
      );
      expect(
        _pinned(VotingErrorCode.values),
        equals({
          'resolutionNotFound': 'resolutionNotFound',
          'notAParticipant': 'notAParticipant',
          'noVotingRights': 'noVotingRights',
          'resolutionClosed': 'resolutionClosed',
          'votingWindowOver': 'votingWindowOver',
          'alreadyVoted': 'alreadyVoted',
        }),
      );
      expect(
        _pinned(VoteDeliveryErrorCode.values),
        equals({
          'undeliverable': 'voteUndeliverable',
          'previouslyRejected': 'votePreviouslyRejected',
          'inProgress': 'voteInProgress',
          'notRejected': 'voteNotRejected',
        }),
      );
      expect(
        _pinned(BiometricErrorCode.values),
        equals({
          'unavailable': 'biometricUnavailable',
          'notEnrolled': 'biometricNotEnrolled',
          'cancelled': 'biometricCancelled',
          'failed': 'biometricFailed',
          'lockedOut': 'biometricLockedOut',
        }),
      );
      expect(
        _pinned(StorageErrorCode.values),
        equals({
          'readFailed': 'storageReadFailed',
          'writeFailed': 'storageWriteFailed',
        }),
      );
      expect(
        _pinned(ScreenProtectionErrorCode.values),
        equals({
          'unsupported': 'screenProtectionUnsupported',
          'failed': 'screenProtectionFailed',
        }),
      );
      expect(
        _pinned(AlreadyVotedSource.values),
        equals({'recorded': 'recorded', 'queued': 'queued'}),
      );
    });

    test('are those of the fields and rules of a validation error', () {
      expect(
        _pinned(ValidationRule.values),
        equals({
          'required': 'required',
          'tooLong': 'tooLong',
          'invalidFormat': 'invalidFormat',
          'notAnInteger': 'notAnInteger',
          'outOfRange': 'outOfRange',
          'unknownValue': 'unknownValue',
          'duplicate': 'duplicate',
        }),
      );
      expect(
        _pinned(ValidationField.values),
        equals({
          'userId': 'userId',
          'meetingId': 'meetingId',
          'agendaItemId': 'agendaItemId',
          'resolutionId': 'resolutionId',
          'documentId': 'documentId',
          'fullName': 'fullName',
          'email': 'email',
          'password': 'password',
          'title': 'title',
          'description': 'description',
          'location': 'location',
          'position': 'position',
          'pageCount': 'pageCount',
          'pageLimit': 'pageLimit',
          'pageCursor': 'pageCursor',
          'instant': 'instant',
          'duration': 'duration',
          'documentLocation': 'documentLocation',
          'attemptCount': 'attemptCount',
          'agenda': 'agenda',
          'documents': 'documents',
          'participants': 'participants',
          'voteChoice': 'voteChoice',
          'meetingPeriod': 'meetingPeriod',
          'participantRole': 'participantRole',
          'resolutionStatus': 'resolutionStatus',
          'confidentialityLevel': 'confidentialityLevel',
        }),
      );
    });
  });

  group('the values that leave the process', () {
    test('include the idempotency key sent to the server: '
        'the length of the resolution id, the resolution id, the voter id', () {
      expect(
        idempotencyKeyOf(aResolutionId('resolution-1'), aUserId('user-1')),
        equals('12.resolution-1.user-1'),
      );
      expect(
        idempotencyKeyOf(aResolutionId('r.1'), aUserId('u:2')),
        equals('3.r.1.u:2'),
      );
    });

    test('include the page sizes asked of the server', () {
      expect(defaultPageLimit, equals(20));
      expect(maxPageLimit, equals(50));
    });
  });
}
