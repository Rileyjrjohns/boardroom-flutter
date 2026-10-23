import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'resolution.freezed.dart';

/// The longest description of a resolution or an agenda item, in UTF-16 code
/// units, once trimmed.
const int maxDescriptionLength = 5000;

/// What the status of a resolution says about its vote.
enum ResolutionStatus implements StableValue {
  /// The vote is open.
  open('open'),

  /// The vote is closed.
  closed('closed');

  new(this.value);

  @override
  final String value;
}

/// Parses the stable string [raw] into a [ResolutionStatus].
Result<ResolutionStatus, ValidationError> parseResolutionStatus(String raw) {
  final status = findConstant(ResolutionStatus.values, raw);
  return status == null
      ? err(
          validationError(
            ValidationField.resolutionStatus,
            ValidationRule.unknownValue,
          ),
        )
      : ok(status);
}

/// A decision the board votes on.
@freezed
abstract class Resolution with _$Resolution {
  /// Creates a resolution from validated parts. Use [createResolution].
  const factory({
    required ResolutionId id,
    required String title,
    required String description,
    required ResolutionStatus status,

    /// The end of the voting window. A resolution without one stays open until
    /// its status says otherwise.
    Instant? closesAt,

    /// The vote the current user has already cast, as the remote source
    /// records it. Null: none yet.
    VoteChoice? recordedVote,
  }) = _Resolution;
}

/// What [createResolution] needs to build a resolution.
final class ResolutionInput {
  /// Creates the input of [createResolution].
  const new({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.closesAt,
    this.recordedVote,
  });

  /// The id of the resolution.
  final ResolutionId id;

  /// The title, trimmed by [createResolution].
  final String title;

  /// The description, trimmed by [createResolution].
  final String description;

  /// Whether the vote is open.
  final ResolutionStatus status;

  /// The end of the voting window, if there is one.
  final Instant? closesAt;

  /// The vote already recorded for the current user, if any.
  final VoteChoice? recordedVote;
}

/// Builds a resolution. The title and the description are trimmed; neither
/// may be blank, and they must not be longer than [maxTitleLength] and
/// [maxDescriptionLength].
Result<Resolution, ValidationError> createResolution(ResolutionInput input) =>
    andThen(
      requireText(ValidationField.title, input.title, maxTitleLength),
      (title) => andThen(
        requireText(
          ValidationField.description,
          input.description,
          maxDescriptionLength,
        ),
        (description) => ok(
          Resolution(
            id: input.id,
            title: title,
            description: description,
            status: input.status,
            closesAt: input.closesAt,
            recordedVote: input.recordedVote,
          ),
        ),
      ),
    );
