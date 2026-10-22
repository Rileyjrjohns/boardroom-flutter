import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';

/// Why a vote was not recorded: a [GatewayError] or a [VotingError]. A
/// `VotingError` is a business rejection: the server understood the vote and
/// refused it (resolution closed, already voted, not eligible), so sending it
/// again changes nothing. A `GatewayError` is a failure of the exchange itself.
typedef VoteSubmissionError = AppError;

/// The remote source that records votes.
abstract interface class VoteRepository {
  /// Sends a vote.
  ///
  /// Contract:
  /// - Never throws. It settles in bounded time; a request that times out is
  ///   `networkUnavailable`.
  /// - Idempotent on `vote.idempotencyKey`: sending a vote the server already
  ///   holds under that key (a retry after the answer was lost) succeeds
  ///   without recording it twice. It never answers `alreadyVoted` to the very
  ///   vote it recorded. A different choice under the same key is a second
  ///   vote, and is rejected as `alreadyVoted`.
  /// - If the voter of the vote is not the user the request is authenticated
  ///   as, the adapter answers `unauthorized`, never a voting error: a vote is
  ///   only ever recorded for the signed-in user, whoever queued it. The user
  ///   the request is authenticated as is the identity attached to the request
  ///   itself, read when it was created, never the one of a user who signed in
  ///   while it was in flight: a vote is not sent under the session of somebody
  ///   else.
  /// - The server must not trust `castAt`. It comes from the clock of the
  ///   device, which the user controls: the server stamps the vote with its own
  ///   time and applies the voting window to it.
  /// - `networkUnavailable` and `unexpected` say nothing about the vote (the
  ///   server may or may not have recorded it), so the vote is kept and sent
  ///   again later; the key makes the replay safe. `unauthorized` stops
  ///   everything until the user signs in again. A voting error is final.
  Future<Result<void, VoteSubmissionError>> submit(Vote vote);
}
