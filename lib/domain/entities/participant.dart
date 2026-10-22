import 'package:boardroom/domain/entities/user.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/constants.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/shared/validation.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'participant.freezed.dart';

/// The part a participant plays in a meeting.
enum ParticipantRole implements StableValue {
  /// Chairs the meeting. Votes.
  chair('chair'),

  /// Takes the minutes. Does not vote.
  secretary('secretary'),

  /// A member of the board. Votes.
  member('member'),

  /// Attends without a vote.
  guest('guest');

  new(this.value);

  @override
  final String value;
}

/// The roles that carry a vote. A secretary takes the minutes and a guest
/// attends: neither votes.
const List<ParticipantRole> _votingRoles = [
  ParticipantRole.chair,
  ParticipantRole.member,
];

/// Parses the stable string [raw] into a [ParticipantRole].
Result<ParticipantRole, ValidationError> parseParticipantRole(String raw) {
  final role = findConstant(ParticipantRole.values, raw);
  return role == null
      ? err(
          validationError(
            ValidationField.participantRole,
            ValidationRule.unknownValue,
          ),
        )
      : ok(role);
}

/// A person invited to a meeting, in a given role.
@freezed
abstract class Participant with _$Participant {
  /// Creates a participant from validated parts. Use [createParticipant].
  const factory({
    required UserId userId,
    required String fullName,
    required ParticipantRole role,
  }) = _Participant;
}

/// Builds a participant. The full name is trimmed; it must not be blank nor
/// longer than [maxFullNameLength].
Result<Participant, ValidationError> createParticipant({
  required UserId userId,
  required String fullName,
  required ParticipantRole role,
}) => map(
  requireText(ValidationField.fullName, fullName, maxFullNameLength),
  (name) => Participant(userId: userId, fullName: name, role: role),
);

/// Whether the participant carries a vote.
bool hasVotingRights(Participant participant) =>
    _votingRoles.contains(participant.role);
