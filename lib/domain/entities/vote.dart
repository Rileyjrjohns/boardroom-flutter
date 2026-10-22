import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/domain/value_objects/vote_choice.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'vote.freezed.dart';

/// Identifies a vote for the remote source, which uses it to recognise a vote
/// it already has: sending the same vote twice (a retry after a lost answer)
/// records it once. Derived from the resolution and the voter, because a
/// member votes once per resolution. The meeting is not part of the key:
/// resolution ids are globally unique (see [ResolutionId]), so the resolution
/// says which meeting the vote is for.
///
/// A `String` at runtime (an extension type), made by [idempotencyKeyOf] only.
extension type const IdempotencyKey._(String _key) implements String;

/// Separates the length of the resolution id, the resolution id and the voter
/// id in the key.
const String _keySeparator = '.';

/// The key of the vote of [voterId] on [resolutionId]:
/// `length.resolutionId.voterId`, where `length` is the length of the
/// resolution id. Deterministic (same inputs, same key), it cannot fail (it
/// only concatenates), and two different pairs never give the same key: the
/// length says where the resolution id ends, so whatever characters the ids
/// contain (separators included), the key can be read back unambiguously.
IdempotencyKey idempotencyKeyOf(ResolutionId resolutionId, UserId voterId) {
  final key = [resolutionId.length, resolutionId, voterId].join(_keySeparator);
  return IdempotencyKey._(key);
}

/// A vote that has been cast. It is final: there is no way to change it.
@freezed
abstract class Vote with _$Vote {
  /// Creates a vote from validated parts. Use [createVote], which derives the
  /// key.
  const factory({
    required ResolutionId resolutionId,
    required MeetingId meetingId,
    required UserId voterId,
    required VoteChoice choice,
    required Instant castAt,
    required IdempotencyKey idempotencyKey,
  }) = _Vote;
}

/// What [createVote] needs to build a vote.
final class VoteInput {
  /// Creates the input of [createVote].
  const new({
    required this.resolutionId,
    required this.meetingId,
    required this.voterId,
    required this.choice,
    required this.castAt,
  });

  /// The resolution voted on.
  final ResolutionId resolutionId;

  /// The meeting the resolution belongs to.
  final MeetingId meetingId;

  /// Who votes.
  final UserId voterId;

  /// What the voter answers.
  final VoteChoice choice;

  /// When the vote is cast.
  final Instant castAt;
}

/// Builds a vote. It cannot fail: every field is already a validated value.
/// Whether the voter may vote is the business of `checkVotingEligibility`,
/// which runs before.
Vote createVote(VoteInput input) => Vote(
  resolutionId: input.resolutionId,
  meetingId: input.meetingId,
  voterId: input.voterId,
  choice: input.choice,
  castAt: input.castAt,
  idempotencyKey: idempotencyKeyOf(input.resolutionId, input.voterId),
);
