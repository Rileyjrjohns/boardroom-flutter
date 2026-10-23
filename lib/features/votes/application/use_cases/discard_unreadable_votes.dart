import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/session/require_session.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/votes/application/ports/vote_outbox.dart';

/// What [DiscardUnreadableVotes] needs: what the session guard needs, and the
/// outbox.
abstract interface class DiscardUnreadableVotesDeps
    implements RequireSessionDeps {
  /// The local queue of votes.
  VoteOutbox get outbox;
}

/// What discarding the unreadable votes fails with: a `SessionRequiredError`, a
/// `SessionChangedError` or a [StorageWriteFailedError].
typedef DiscardUnreadableVotesError = AppError;

/// The user asks to be rid of the entries of their outbox that can no longer be
/// read as a vote (see `VoteOutbox`): they are deleted for good, and the answer
/// is how many there were. Nothing else deletes them: a read, a vote queued
/// under their key and a synchronisation all leave them where they are, because
/// an entry nobody can read may still be the only trace of a vote. The screen
/// says how many there are before it asks, and asks for a confirmation.
///
/// Requires a valid session; only the entries of the signed-in user are
/// discarded. Asking again discards nothing and says zero.
///
/// The user is checked again once the outbox has answered (`requireSameUser`):
/// the count is told to nobody else than the user it concerns, so if somebody
/// else is signed in by then, or the app is locked, the answer is
/// `sessionChanged` (or `appLocked`) and nothing is logged. The entries of the
/// user who asked are gone either way: they confirmed it.
final class DiscardUnreadableVotes {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final DiscardUnreadableVotesDeps _deps;

  /// Discards the unreadable entries of the signed-in user.
  Future<Result<int, DiscardUnreadableVotesError>> execute() async {
    final Session session;
    switch (await requireSession(_deps)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        session = value;
    }

    final int discarded;
    switch (await _deps.outbox.discardUnreadable(session.user.id)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        discarded = value;
    }

    final stillTheUser = await requireSameUser(_deps, session.user.id);
    if (stillTheUser case Err(:final error)) {
      return err(error);
    }

    _deps.monitoring.log(
      LogLevel.warn,
      MonitoringEvent.unreadableVotesDiscarded,
      {LogAttribute.discarded: discarded},
    );
    return ok(discarded);
  }
}
