import 'package:boardroom/application/ports/vote_outbox.dart';
import 'package:boardroom/application/shared/require_session.dart';
import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/domain/entities/session.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'list_pending_votes.freezed.dart';

/// What [ListPendingVotes] needs: what the session guard needs, and the outbox.
abstract interface class ListPendingVotesDeps implements RequireSessionDeps {
  /// The local queue of votes.
  VoteOutbox get outbox;
}

/// The votes of the signed-in user in the outbox, told apart by their state.
/// Oldest first.
@freezed
abstract class OutboxContent with _$OutboxContent {
  /// Creates the content.
  const factory({
    /// Waiting to be sent.
    required List<PendingVote> pending,

    /// Refused or given up, with the reason. They stay until the user
    /// acknowledges them.
    required List<RejectedVote> rejected,

    /// How many entries of the user are kept but cannot be read as a vote any
    /// more. They are neither sent nor shown, and stay until the user discards
    /// them (`DiscardUnreadableVotes`).
    required int unreadable,
  }) = _OutboxContent;
}

/// What listing the votes fails with: a `SessionRequiredError`, a
/// `SessionChangedError` or a [StorageReadFailedError].
typedef ListPendingVotesError = AppError;

/// The votes of the signed-in user that wait in the outbox, and the ones that
/// ended rejected. The outbox is shared by everybody who signs in on the
/// device: the votes of another user are never read (the port is scoped by
/// voter). It also says how many entries of the user cannot be read: the user
/// is told, and decides whether to discard them.
///
/// The read takes time, and the user can sign out (or somebody else sign in)
/// while it is in flight: the session is checked again once it answers
/// (`requireSameUser`), and the entries are returned to nobody else than the
/// user they belong to (`sessionChanged`, or `appLocked` if the app was locked
/// meanwhile).
final class ListPendingVotes {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final ListPendingVotesDeps _deps;

  /// Lists the votes of the signed-in user.
  Future<Result<OutboxContent, ListPendingVotesError>> execute() async {
    final Session session;
    switch (await requireSession(_deps)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        session = value;
    }

    final OutboxListing listed;
    switch (await _deps.outbox.list(session.user.id)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        listed = value;
    }

    final stillTheUser = await requireSameUser(_deps, session.user.id);
    if (stillTheUser case Err(:final error)) {
      return err(error);
    }

    final OutboxListing(:votes, :unreadable) = listed;
    return ok(
      OutboxContent(
        pending: votes.whereType<PendingVote>().toList(),
        rejected: votes.whereType<RejectedVote>().toList(),
        unreadable: unreadable,
      ),
    );
  }
}
