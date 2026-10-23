import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/application/session/confirm_with_biometrics.dart';
import 'package:boardroom/features/auth/application/session/end_session.dart';
import 'package:boardroom/features/auth/application/session/require_session.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart'
    show BiometricError;
import 'package:boardroom/features/meetings/application/load_meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/ports/recorded_vote_sink.dart';
import 'package:boardroom/features/votes/application/ports/vote_outbox.dart';
import 'package:boardroom/features/votes/application/ports/vote_repository.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/domain/policies/voting_eligibility.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'cast_vote.freezed.dart';

/// What [CastVote] needs, on top of what [loadMeeting] needs: the outbox, the
/// server that records votes, and the biometric prompt.
abstract interface class CastVoteDeps implements LoadMeetingDeps {
  /// The local queue of votes that could not be delivered.
  VoteOutbox get outbox;

  /// The server that records votes.
  VoteRepository get votes;

  /// The biometric prompt that confirms a vote.
  BiometricGate get biometricGate;

  /// Where a vote the server recorded is written into the cached meeting.
  RecordedVoteSink get recordedVoteSink;
}

/// What happened to a vote that was cast.
enum CastVoteStatus implements StableValue {
  /// The server has recorded it.
  submitted('submitted'),

  /// It could not be delivered now: it waits in the outbox, and
  /// `SyncPendingVotes` will send it.
  queued('queued');

  new(this.value);

  @override
  final String value;
}

/// What [CastVote] answers: the [status] of the vote and the [vote] itself.
@freezed
abstract class CastVoteOutcome with _$CastVoteOutcome {
  /// Creates an outcome.
  const factory({
    /// Whether the vote was recorded or queued.
    required CastVoteStatus status,

    /// The vote that was cast.
    required Vote vote,
  }) = _CastVoteOutcome;
}

/// What casting a vote fails with: a `SessionRequiredError`, a
/// `SessionChangedError`, a [RepositoryError], a [StorageError], a
/// [VotingError], a [BiometricError], a [VoteInProgressError] or a
/// [VotePreviouslyRejectedError].
typedef CastVoteError = AppError;

/// Why a vote could not be queued: an entry of the outbox that cannot be read
/// holds its key.
const String _unreadableEntryCause = 'unreadable entry holds the key';

/// Casts the vote of the signed-in user on a resolution. A cast vote is final.
/// Steps:
///
/// 1. refuses at once (`voteInProgress`) when a vote on the same resolution is
///    being cast by this instance, whatever the choice: the first one is
///    waiting for the biometric prompt, say;
/// 2. requires a valid session (its user is the voter);
/// 3. loads the meeting with the offline policy of `loadWithCacheFallback`, so
///    a member can vote from a meeting already seen without network;
/// 4. checks the eligibility (see `checkVotingEligibility`), including a vote
///    of the same voter already waiting in the outbox, and refuses
///    (`votePreviouslyRejected`) when an earlier vote of the voter on this
///    resolution is in the outbox, rejected, until they acknowledge it. The
///    meeting may be a stale copy: the server has the last word;
/// 5. asks for the biometric confirmation, only now that the vote is allowed,
///    so that nobody is prompted for a vote that cannot be cast;
/// 6. checks again that the same user is still signed in and the app still
///    unlocked, because the prompt can take long: otherwise the answer is
///    `sessionChanged` (or `appLocked`) and nothing is submitted or queued;
/// 7. builds the vote with the clock and submits it.
///
/// Submitted: `status: submitted`, and the cached copy of the meeting records
/// the vote. The network is down, or the server failed in a way that says
/// nothing about the vote (`unexpected`: it may have recorded it): the vote is
/// put in the outbox and the status is `queued`; the idempotency key makes the
/// later replay safe. A business rejection (such as `resolutionClosed` or
/// `alreadyVoted`) is returned as an error and nothing is queued. So is
/// `unauthorized`, the server no longer accepting the session: it ends the
/// session on the device (see `endRefusedSession`), and the vote is not
/// queued: the user signs in again and casts it again. If the outbox itself
/// refuses the vote, the failure is captured and returned.
///
/// The guard of step 1 is a field of the instance, set before the first
/// `await`, and released whatever happens: the composition root must share one
/// instance. It does not cover two instances (two screens built with their
/// own). There the outbox, which holds one vote per voter and resolution,
/// makes the second one fail with `alreadyVoted` if both are queued, and the
/// server does the same if both are submitted.
final class CastVote {
  /// Creates the use case over [_deps].
  new(this._deps);

  final CastVoteDeps _deps;
  final Set<ResolutionId> _inFlight = {};

  /// Casts the vote of [choice] on [resolutionId] of [meetingId].
  Future<Result<CastVoteOutcome, CastVoteError>> execute({
    required MeetingId meetingId,
    required ResolutionId resolutionId,
    required VoteChoice choice,
  }) async {
    if (_inFlight.contains(resolutionId)) {
      return err(voteInProgress());
    }

    _inFlight.add(resolutionId);
    try {
      return await _cast(meetingId, resolutionId, choice);
    } finally {
      _inFlight.remove(resolutionId);
    }
  }

  Future<Result<CastVoteOutcome, CastVoteError>> _cast(
    MeetingId meetingId,
    ResolutionId resolutionId,
    VoteChoice choice,
  ) async {
    final CastVoteDeps(:clock, :outbox, :biometricGate) = _deps;

    final Session session;
    switch (await requireSession(_deps)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        session = value;
    }
    final voterId = session.user.id;

    final Meeting meeting;
    switch (await loadMeeting(_deps, voterId, meetingId)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        meeting = value.data;
    }

    final List<OutboxVote> found;
    switch (await outbox.findByResolution(resolutionId, voterId)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        found = value;
    }

    final eligible = checkVotingEligibility(
      VotingEligibilityInput(
        meeting: meeting,
        resolutionId: resolutionId,
        voterId: voterId,
        queuedVotes: found.whereType<PendingVote>().toList(),
        now: clock.now(),
      ),
    );
    if (eligible case Err(:final error)) {
      return err(error);
    }

    final rejected = found.whereType<RejectedVote>().firstOrNull;
    if (rejected != null) {
      return err(votePreviouslyRejected(rejected.reason));
    }

    final confirmed = await confirmWithBiometrics(
      biometricGate,
      BiometricReason.confirmVote,
    );
    if (confirmed case Err(:final error)) {
      return err(error);
    }

    // The prompt waits for the user, as long as they like: the one who confirms
    // is the one who voted only if the session and the lock are still what they
    // were when the prompt was shown.
    final stillSignedIn = await requireSameUser(_deps, voterId);
    if (stillSignedIn case Err(:final error)) {
      return err(error);
    }

    return await _send(
      createVote(
        VoteInput(
          resolutionId: resolutionId,
          meetingId: meetingId,
          voterId: voterId,
          choice: choice,
          castAt: clock.now(),
        ),
      ),
    );
  }

  Future<Result<CastVoteOutcome, CastVoteError>> _send(Vote vote) async {
    final CastVoteDeps(:votes, :monitoring) = _deps;
    final attributes = <LogAttribute, Object>{
      LogAttribute.meetingId: vote.meetingId,
      LogAttribute.resolutionId: vote.resolutionId,
    };

    switch (await votes.submit(vote)) {
      case Ok():
        await _deps.recordedVoteSink.record(vote);
        monitoring.log(
          LogLevel.info,
          MonitoringEvent.voteSubmitted,
          attributes,
        );
        return ok(
          CastVoteOutcome(status: CastVoteStatus.submitted, vote: vote),
        );
      case Err(:final error):
        if (error.code == RepositoryErrorCode.networkUnavailable.value ||
            error.code == RepositoryErrorCode.unexpected.value) {
          return await _queue(vote, error);
        }

        if (isVotingError(error)) {
          monitoring.log(LogLevel.warn, MonitoringEvent.voteRejected, {
            ...attributes,
            LogAttribute.errorCode: error.code,
          });
        } else if (error.code == RepositoryErrorCode.unauthorized.value) {
          await endRefusedSession(_deps, vote.voterId);
        }
        return err(error);
    }
  }

  /// Keeps a vote that could not be delivered, to be sent later. [cause] is the
  /// answer of the server that says nothing about the vote: the network is
  /// unavailable, or the server failed unexpectedly.
  Future<Result<CastVoteOutcome, CastVoteError>> _queue(
    Vote vote,
    AppError cause,
  ) async {
    final CastVoteDeps(:clock, :outbox, :monitoring) = _deps;
    final attributes = <LogAttribute, Object>{
      LogAttribute.meetingId: vote.meetingId,
      LogAttribute.resolutionId: vote.resolutionId,
    };

    // An unexpected answer is swallowed here, and counts as an attempt: capture
    // it.
    final failedOnServer = cause.code == RepositoryErrorCode.unexpected.value;
    if (failedOnServer) {
      monitoring.captureError(
        MonitoringEvent.voteSubmitFailed,
        cause,
        attributes,
      );
    }
    final pending = createPendingVote(vote, clock.now());

    final EnqueueResult enqueued;
    switch (await outbox.enqueue(
      failedOnServer ? recordAttempt(pending) : pending,
    )) {
      case Err(:final error):
        monitoring.captureError(
          MonitoringEvent.voteEnqueueFailed,
          error,
          attributes,
        );
        return err(error);
      case Ok(:final value):
        enqueued = value;
    }

    switch (enqueued) {
      case HeldByUnreadable():
        // An entry nobody can read sits under the key of this vote. It is not
        // overwritten: the vote is not queued, and the failure says why. The
        // user can discard the entry from the list of pending votes, and cast
        // the vote again.
        final blocked = storageWriteFailed(_unreadableEntryCause);
        monitoring.captureError(
          MonitoringEvent.voteEnqueueFailed,
          blocked,
          attributes,
        );
        return err(blocked);
      case AlreadyQueued(:final existing):
        return err(switch (existing) {
          PendingVote() => const AlreadyVotedError(
            source: AlreadyVotedSource.queued,
          ),
          RejectedVote(:final reason) => votePreviouslyRejected(reason),
        });
      case Enqueued():
        monitoring.log(LogLevel.info, MonitoringEvent.voteQueued, attributes);
        return ok(CastVoteOutcome(status: CastVoteStatus.queued, vote: vote));
    }
  }
}
