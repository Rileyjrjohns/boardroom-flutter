import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/errors/error_catalog.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/use_cases/cast_vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/l10n/app_localizations.dart';

// The domain and the application speak in codes and carry no text. These maps
// and functions are where a code of the votes becomes a text. Each map is keyed
// by the stable string of the code, each function is total (the `unexpected`
// text is the fallback), and a test checks that every code of a family has an
// entry in both languages.

/// The label of a choice of vote.
String voteChoiceLabel(AppLocalizations l10n, VoteChoice choice) =>
    switch (choice) {
      VoteChoice.forChoice => l10n.votesVoteChoiceFor,
      VoteChoice.against => l10n.votesVoteChoiceAgainst,
      VoteChoice.abstain => l10n.votesVoteChoiceAbstain,
    };

/// The label of the role of a participant.
String participantRoleLabel(AppLocalizations l10n, ParticipantRole role) =>
    switch (role) {
      ParticipantRole.chair => l10n.meetingsParticipantRoleChair,
      ParticipantRole.secretary => l10n.meetingsParticipantRoleSecretary,
      ParticipantRole.member => l10n.meetingsParticipantRoleMember,
      ParticipantRole.guest => l10n.meetingsParticipantRoleGuest,
    };

/// Where the earlier vote of the voter is: recorded by the server, or still
/// waiting to be sent.
String alreadyVotedMessage(AppLocalizations l10n, AlreadyVotedSource source) =>
    switch (source) {
      AlreadyVotedSource.recorded => l10n.votesVotingReasonAlreadyVotedRecorded,
      AlreadyVotedSource.queued => l10n.votesVotingReasonAlreadyVotedQueued,
    };

/// Why a vote cannot be cast or was refused, in words. The wording is the same
/// whether the rule is told before the vote (the resolution is closed) or after
/// (the server refused it).
String votingReasonMessage(AppLocalizations l10n, VotingError error) =>
    switch (error) {
      ResolutionNotFoundError() => l10n.votesVotingReasonResolutionNotFound,
      NotAParticipantError() => l10n.votesVotingReasonNotAParticipant,
      NoVotingRightsError() => l10n.votesVotingReasonNoVotingRights,
      ResolutionClosedError() => l10n.votesVotingReasonResolutionClosed,
      VotingWindowOverError() => l10n.votesVotingReasonVotingWindowOver,
      AlreadyVotedError(:final source) => alreadyVotedMessage(l10n, source),
    };

/// Why a vote ended rejected, in words: a rule of the vote, or the app giving
/// up after a number of attempts (a count, written in the language of the
/// user).
String rejectionReasonMessage(AppLocalizations l10n, RejectionReason reason) =>
    switch (reason) {
      VoteUndeliverableError(:final attempts) =>
        l10n.votesVotingReasonVoteUndeliverable(attempts),
      VotingError() => votingReasonMessage(l10n, reason),
    };

/// What the voting block says about a vote that was rejected.
String rejectedVoteMessage(AppLocalizations l10n, RejectionReason reason) =>
    l10n.votesVotingRejected(rejectionReasonMessage(l10n, reason));

/// What a cast vote leaves to say once the choices are gone. A vote that the
/// server recorded is told once, by a message of the screen. A vote that waits
/// to be sent is not told by a message that outlives the wait: the state of the
/// resolution says it for as long as it is true, so that the words go when the
/// vote is sent or refused.
String? castOutcomeMessage(AppLocalizations l10n, CastVoteStatus status) =>
    switch (status) {
      CastVoteStatus.submitted => l10n.votesVotingSubmitted,
      CastVoteStatus.queued => null,
    };

/// Every way casting a vote can fail, and what the confirmation says about it.
/// `alreadyVoted` also depends on the source: see [castVoteErrorMessage].
final Map<String, ErrorMessage> castVoteErrorMessages = Map.unmodifiable({
  AuthenticationErrorCode.notAuthenticated.value: (AppLocalizations l) =>
      l.coreErrorsNotAuthenticated,
  AuthenticationErrorCode.sessionExpired.value: (AppLocalizations l) =>
      l.coreErrorsSessionExpired,
  AuthenticationErrorCode.appLocked.value: (AppLocalizations l) =>
      l.coreErrorsAppLocked,
  AuthenticationErrorCode.sessionChanged.value: (AppLocalizations l) =>
      l.coreErrorsSessionChanged,
  RepositoryErrorCode.networkUnavailable.value: (AppLocalizations l) =>
      l.coreErrorsNetworkUnavailable,
  RepositoryErrorCode.unauthorized.value: (AppLocalizations l) =>
      l.coreErrorsUnauthorized,
  RepositoryErrorCode.forbidden.value: (AppLocalizations l) =>
      l.coreErrorsForbidden,
  RepositoryErrorCode.notFound.value: (AppLocalizations l) =>
      l.coreErrorsNotFound,
  RepositoryErrorCode.unexpected.value: (AppLocalizations l) =>
      l.coreErrorsUnexpected,
  StorageErrorCode.readFailed.value: (AppLocalizations l) =>
      l.coreErrorsStorageReadFailed,
  StorageErrorCode.writeFailed.value: (AppLocalizations l) =>
      l.votesVotingFailureStorageWriteFailed,
  VotingErrorCode.resolutionNotFound.value: (AppLocalizations l) =>
      l.votesVotingReasonResolutionNotFound,
  VotingErrorCode.notAParticipant.value: (AppLocalizations l) =>
      l.votesVotingReasonNotAParticipant,
  VotingErrorCode.noVotingRights.value: (AppLocalizations l) =>
      l.votesVotingReasonNoVotingRights,
  VotingErrorCode.resolutionClosed.value: (AppLocalizations l) =>
      l.votesVotingReasonResolutionClosed,
  VotingErrorCode.votingWindowOver.value: (AppLocalizations l) =>
      l.votesVotingReasonVotingWindowOver,
  VotingErrorCode.alreadyVoted.value: (AppLocalizations l) =>
      l.votesVotingReasonAlreadyVotedRecorded,
  BiometricErrorCode.unavailable.value: (AppLocalizations l) =>
      l.votesVoteBiometricBiometricUnavailable,
  BiometricErrorCode.notEnrolled.value: (AppLocalizations l) =>
      l.votesVoteBiometricBiometricNotEnrolled,
  BiometricErrorCode.cancelled.value: (AppLocalizations l) =>
      l.votesVoteBiometricBiometricCancelled,
  BiometricErrorCode.failed.value: (AppLocalizations l) =>
      l.votesVoteBiometricBiometricFailed,
  BiometricErrorCode.lockedOut.value: (AppLocalizations l) =>
      l.votesVoteBiometricBiometricLockedOut,
  VoteDeliveryErrorCode.inProgress.value: (AppLocalizations l) =>
      l.votesVotingFailureVoteInProgress,
  VoteDeliveryErrorCode.previouslyRejected.value: (AppLocalizations l) =>
      l.votesVotingFailureVotePreviouslyRejected,
});

/// What the confirmation of a vote says when casting it failed.
String castVoteErrorMessage(AppLocalizations l10n, AppError error) {
  if (error is AlreadyVotedError) {
    return alreadyVotedMessage(l10n, error.source);
  }
  return (castVoteErrorMessages[error.code] ??
      castVoteErrorMessages[RepositoryErrorCode.unexpected.value]!)(l10n);
}

/// Every way discarding the unreadable entries of the outbox can fail.
final Map<String, ErrorMessage> discardErrorMessages = Map.unmodifiable({
  AuthenticationErrorCode.notAuthenticated.value: (AppLocalizations l) =>
      l.coreErrorsNotAuthenticated,
  AuthenticationErrorCode.sessionExpired.value: (AppLocalizations l) =>
      l.coreErrorsSessionExpired,
  AuthenticationErrorCode.appLocked.value: (AppLocalizations l) =>
      l.coreErrorsAppLocked,
  AuthenticationErrorCode.sessionChanged.value: (AppLocalizations l) =>
      l.coreErrorsSessionChanged,
  StorageErrorCode.readFailed.value: (AppLocalizations l) =>
      l.coreErrorsStorageReadFailed,
  StorageErrorCode.writeFailed.value: (AppLocalizations l) =>
      l.votesPendingVotesDiscardFailed,
  RepositoryErrorCode.unexpected.value: (AppLocalizations l) =>
      l.coreErrorsUnexpected,
});

/// What the confirmation of the discard says when it failed.
String discardErrorMessage(AppLocalizations l10n, String code) =>
    (discardErrorMessages[code] ??
    discardErrorMessages[RepositoryErrorCode.unexpected.value]!)(l10n);

/// Every way acknowledging a rejected vote can fail.
final Map<String, ErrorMessage> acknowledgeErrorMessages = Map.unmodifiable({
  AuthenticationErrorCode.notAuthenticated.value: (AppLocalizations l) =>
      l.coreErrorsNotAuthenticated,
  AuthenticationErrorCode.sessionExpired.value: (AppLocalizations l) =>
      l.coreErrorsSessionExpired,
  AuthenticationErrorCode.appLocked.value: (AppLocalizations l) =>
      l.coreErrorsAppLocked,
  AuthenticationErrorCode.sessionChanged.value: (AppLocalizations l) =>
      l.coreErrorsSessionChanged,
  StorageErrorCode.readFailed.value: (AppLocalizations l) =>
      l.coreErrorsStorageReadFailed,
  StorageErrorCode.writeFailed.value: (AppLocalizations l) =>
      l.votesVotingFailureStorageWriteFailed,
  VoteDeliveryErrorCode.notRejected.value: (AppLocalizations l) =>
      l.votesVotingFailureVoteNotRejected,
  RepositoryErrorCode.unexpected.value: (AppLocalizations l) =>
      l.coreErrorsUnexpected,
});

/// What the acknowledge button says when it failed.
String acknowledgeErrorMessage(AppLocalizations l10n, String code) =>
    (acknowledgeErrorMessages[code] ??
    acknowledgeErrorMessages[RepositoryErrorCode.unexpected.value]!)(l10n);

/// The failures after which pressing "confirm" again can work, beyond the ones
/// a query may be tried again for (the connection, a fault of the server, a
/// store that could not be read): the prompt was cancelled or did not recognise
/// the user, the device refused to let them try for a while, the vote could not
/// be saved. Every other one is final for this vote (the resolution closed, the
/// user voted elsewhere, the device cannot do biometrics, the session is over).
final Set<String> retryableByTheUser = Set.unmodifiable({
  BiometricErrorCode.cancelled.value,
  BiometricErrorCode.failed.value,
  BiometricErrorCode.lockedOut.value,
  StorageErrorCode.writeFailed.value,
});
