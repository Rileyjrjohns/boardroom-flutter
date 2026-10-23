import 'package:boardroom/application/ports/vote_repository.dart';
import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_backend.dart';

/// The votes of the simulated server. A thin window on the backend it shares
/// with the others.
final class InMemoryVoteRepository implements VoteRepository {
  /// Creates the repository over `backend`.
  const new(this._backend);

  final InMemoryBackend _backend;

  @override
  Future<Result<void, VoteSubmissionError>> submit(Vote vote) =>
      _backend.submitVote(vote);
}
