import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/core/infrastructure/http/gateway_errors.dart';
import 'package:boardroom/core/infrastructure/http/http_client.dart';
import 'package:boardroom/core/infrastructure/http/invalid_response.dart';
import 'package:boardroom/core/infrastructure/http/protocol.dart';
import 'package:boardroom/core/infrastructure/http/well_formed.dart';
import 'package:boardroom/features/votes/application/ports/vote_repository.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:boardroom/features/votes/infrastructure/dto/vote_dto.dart';
import 'package:boardroom/features/votes/infrastructure/rejection_schemas.dart';

/// The votes of the API (`POST /votes`). The request carries the idempotency
/// key in a header, so that a retry after a lost answer is recorded once; the
/// key is percent-encoded, because the ids it is made of are free text. A vote
/// the server refuses by a business rule (422) is a voting error, and sending
/// it again changes nothing.
///
/// The request is made for the voter (`forUser`): the client sends it only with
/// the token of that user, and answers `unauthorized`, without sending, if
/// somebody else is signed in by then. So a vote is never recorded under the
/// session of another user, whatever the server checks. The body of a success
/// carries nothing the app needs and is not read: a success is a success,
/// whatever it says.
final class HttpVoteRepository implements VoteRepository {
  /// Creates the repository over `client`.
  const new(this._client, this._monitoring);

  final HttpClient _client;
  final Monitoring _monitoring;

  @override
  Future<Result<void, VoteSubmissionError>> submit(Vote vote) async {
    final answer = await _client.perform(
      () => HttpActionSpec(
        method: HttpMethod.post,
        path: Routes.votes,
        headers: {
          HttpHeader.idempotencyKey.value: encodeUriComponent(
            vote.idempotencyKey,
          ),
        },
        body: toVoteRequestWire(vote).toJson(),
        forUser: vote.voterId,
        resource: HttpResource.vote,
      ),
    );
    final HttpFailure failure;
    switch (answer) {
      case Ok():
        return ok<void>(null);
      case Err(:final error):
        failure = error;
    }
    if (failure is! RequestRejected) {
      return err(asGatewayError(failure));
    }

    final VotingErrorWire described;
    switch (decodeWire(failure.error, votingErrorWireFromJson)) {
      case Err(:final error):
        return err(
          schemaViolation(_monitoring, HttpResource.vote, error.issuePaths),
        );
      case Ok(:final value):
        described = value;
    }
    switch (toVotingError(described)) {
      case Ok(:final value):
        return err(value);
      case Err(:final error):
        return err(domainViolation(_monitoring, HttpResource.vote, error));
    }
  }
}
