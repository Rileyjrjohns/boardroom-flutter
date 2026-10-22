import 'package:boardroom/application/ports/vote_outbox.dart';
import 'package:boardroom/application/shared/require_session.dart';
import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/domain/entities/session.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';

/// What [AcknowledgeRejectedVote] needs: what the session guard needs, and the
/// outbox.
abstract interface class AcknowledgeRejectedVoteDeps
    implements RequireSessionDeps {
  /// The local queue of votes.
  VoteOutbox get outbox;
}

/// What acknowledging a rejected vote fails with: a `SessionRequiredError`, a
/// `SessionChangedError`, a [StorageError] or a [VoteNotRejectedError].
typedef AcknowledgeRejectedVoteError = AppError;

/// The user has seen that their vote on a resolution was rejected: deletes it
/// from the outbox. Requires a valid session; only the vote of the signed-in
/// user can be acknowledged. A vote that is still pending is not touched
/// (`voteNotRejected`): it is deleted by being sent, never by acknowledging. A
/// resolution with no vote in the outbox is not an error (nothing to do), so a
/// double tap is harmless.
///
/// The user is checked again once the outbox has answered (`requireSameUser`):
/// if somebody else is signed in by then, or the app is locked, nothing is
/// deleted and the answer is `sessionChanged` (or `appLocked`).
final class AcknowledgeRejectedVote {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final AcknowledgeRejectedVoteDeps _deps;

  /// Acknowledges the rejected vote on [resolutionId].
  Future<Result<void, AcknowledgeRejectedVoteError>> execute({
    required ResolutionId resolutionId,
  }) async {
    final outbox = _deps.outbox;

    final Session session;
    switch (await requireSession(_deps)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        session = value;
    }

    final List<OutboxVote> found;
    switch (await outbox.findByResolution(resolutionId, session.user.id)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        found = value;
    }

    final stillTheUser = await requireSameUser(_deps, session.user.id);
    if (stillTheUser case Err(:final error)) {
      return err(error);
    }

    final entry = found.firstOrNull;
    if (entry == null) {
      return ok<void>(null);
    }
    if (entry is PendingVote) {
      return err(voteNotRejected());
    }

    return await outbox.remove(entry.vote.idempotencyKey);
  }
}
