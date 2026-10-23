import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:json_annotation/json_annotation.dart';

part 'vote_dto.g.dart';

// Casting a vote: `POST /votes`. The answer carries no body; a business
// rejection is a 422 whose body is described in
// `core/infrastructure/shared/rejection_schemas.dart`.

/// The body of `POST /votes`.
@JsonSerializable(checked: true)
final class VoteRequestWire {
  /// Creates the wire form of a vote.
  const new({
    required this.resolutionId,
    required this.meetingId,
    required this.voterId,
    required this.choice,
    required this.castAt,
  });

  /// Reads the body of a vote request, or throws a `CheckedFromJsonException`
  /// at the first field that is missing or has the wrong type. Fields it does
  /// not know (an idempotency key it did not derive, say) are ignored.
  factory fromJson(Map<String, dynamic> json) =>
      _$VoteRequestWireFromJson(json);

  /// The resolution voted on.
  final String resolutionId;

  /// The meeting of the resolution.
  final String meetingId;

  /// The user who voted.
  final String voterId;

  /// The choice, as the API names it.
  final String choice;

  /// When the voter chose, on the clock of their device, in milliseconds since
  /// the epoch (an ISO 8601 text on the wire). The server does not trust it.
  @JsonKey(fromJson: readInstantMillis, toJson: writeInstantMillis)
  final int castAt;

  /// The JSON object of this request.
  Map<String, dynamic> toJson() => _$VoteRequestWireToJson(this);
}

/// A vote, written without its key: the key is derived from the resolution and
/// the voter.
VoteRequestWire toVoteRequestWire(Vote vote) => VoteRequestWire(
  resolutionId: vote.resolutionId,
  meetingId: vote.meetingId,
  voterId: vote.voterId,
  choice: vote.choice.value,
  castAt: vote.castAt,
);

/// The vote a request carries, through the factories of the domain: what the
/// server reads.
Result<Vote, ValidationError> toVote(VoteRequestWire wire) => andThen(
  parseResolutionId(wire.resolutionId),
  (resolutionId) => andThen(
    parseMeetingId(wire.meetingId),
    (meetingId) => andThen(
      parseUserId(wire.voterId),
      (voterId) => andThen(
        parseVoteChoice(wire.choice),
        (choice) => andThen(
          parseInstant(wire.castAt),
          (castAt) => ok(
            createVote(
              VoteInput(
                resolutionId: resolutionId,
                meetingId: meetingId,
                voterId: voterId,
                choice: choice,
                castAt: castAt,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
