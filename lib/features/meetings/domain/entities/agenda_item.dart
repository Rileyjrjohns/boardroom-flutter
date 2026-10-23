import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'agenda_item.freezed.dart';

const int _maxAgendaPosition = 1000;

/// One point of the agenda of a meeting, possibly submitted to a vote.
@freezed
abstract class AgendaItem with _$AgendaItem {
  /// Creates an agenda item from validated parts. Use [createAgendaItem].
  const factory({
    required AgendaItemId id,

    /// Order in the agenda, starting at 1.
    required int position,
    required String title,
    String? description,
    Resolution? resolution,
  }) = _AgendaItem;
}

/// What [createAgendaItem] needs to build an agenda item.
final class AgendaItemInput {
  /// Creates the input of [createAgendaItem].
  const new({
    required this.id,
    required this.position,
    required this.title,
    this.description,
    this.resolution,
  });

  /// The id of the agenda item.
  final AgendaItemId id;

  /// A whole number between 1 and 1000. It is a `num` because it comes from
  /// outside (a decoded answer) and may be a fraction.
  final num position;

  /// The title, trimmed by [createAgendaItem].
  final String title;

  /// A blank description is no description.
  final String? description;

  /// The resolution submitted to a vote, if any.
  final Resolution? resolution;
}

/// Builds an agenda item. The position must be a whole number between 1 and
/// 1000, the title is trimmed and must not be blank nor longer than
/// [maxTitleLength], and a blank description is dropped.
Result<AgendaItem, ValidationError> createAgendaItem(AgendaItemInput input) =>
    andThen(
      requireIntegerInRange(
        ValidationField.position,
        input.position,
        1,
        _maxAgendaPosition,
      ),
      (position) => andThen(
        requireText(ValidationField.title, input.title, maxTitleLength),
        (title) => andThen(
          optionalText(
            ValidationField.description,
            input.description,
            maxDescriptionLength,
          ),
          (description) => ok(
            AgendaItem(
              id: input.id,
              position: position,
              title: title,
              description: description,
              resolution: input.resolution,
            ),
          ),
        ),
      ),
    );
