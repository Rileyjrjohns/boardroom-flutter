import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/votes/application/ports/vote_repository.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';

import 'fake_auth_session.dart';
import 'fake_network.dart';

/// A server that records votes and honours the contract of the port: idempotent
/// on the key, and `unauthorized` for a vote whose voter is not the user the
/// request is authenticated as (the session of the fake auth). The answers of
/// the next calls can be scripted, to simulate a refusal or a connection that
/// drops half way through a synchronisation.
class FakeVoteRepository implements VoteRepository {
  /// Creates a server that goes down with [_network] and authenticates requests
  /// with the session of [_auth].
  new(this._network, this._auth);

  final FakeNetwork _network;
  final FakeAuthSession _auth;

  /// Every vote received, including the ones that were refused.
  final List<Vote> received = [];

  /// Called with each vote when it arrives, before the server answers: a test
  /// uses it to change the world in the middle of a synchronisation (another
  /// user signs in, say).
  void Function(Vote vote)? onReceive;

  final List<Result<void, VoteSubmissionError>> _scripted = [];
  final Map<IdempotencyKey, Vote> _recorded = {};

  /// The votes the server holds.
  List<Vote> recordedVotes() => List.of(_recorded.values);

  /// Answers the next call with [answer] instead of the normal behaviour; a
  /// success scripted this way records the vote. Answers are used in the order
  /// they are queued.
  void answerNext(Result<void, VoteSubmissionError> answer) {
    _scripted.add(answer);
  }

  @override
  Future<Result<void, VoteSubmissionError>> submit(Vote vote) async {
    received.add(vote);
    onReceive?.call(vote);
    final answer = _scripted.isEmpty
        ? _defaultAnswer(vote)
        : _scripted.removeAt(0);
    if (answer is Ok<void, VoteSubmissionError>) {
      _recorded[vote.idempotencyKey] = vote;
    }
    return answer;
  }

  Result<void, VoteSubmissionError> _defaultAnswer(Vote vote) {
    if (!_network.online) {
      return err(networkUnavailable());
    }
    if (_auth.session?.user.id != vote.voterId) {
      return err(unauthorized());
    }
    final held = _recorded[vote.idempotencyKey];
    if (held != null && held.choice != vote.choice) {
      return err(const AlreadyVotedError(source: AlreadyVotedSource.recorded));
    }
    return ok<void>(null);
  }
}
