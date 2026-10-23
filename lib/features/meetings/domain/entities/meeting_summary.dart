import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'meeting_summary.freezed.dart';

const int _maxLocationLength = 300;

/// What a list of meetings shows about a meeting. A `Meeting` has all of it
/// too (it implements this class).
// A Meeting implements this class, and both would declare a `copyWith` of
// their own type: the summary gives it up.
@Freezed(copyWith: false)
abstract class MeetingSummary with _$MeetingSummary {
  /// Creates a summary from validated parts. Use [createMeetingSummary].
  const factory({
    required MeetingId id,
    required String title,
    required Instant scheduledAt,

    /// Where it takes place: a room, an address, a video call. Free text.
    required String location,
  }) = _MeetingSummary;
}

/// What [createMeetingSummary] needs to build a summary.
final class MeetingSummaryInput {
  /// Creates the input of [createMeetingSummary].
  const new({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.location,
  });

  /// The id of the meeting.
  final MeetingId id;

  /// The title, trimmed by [createMeetingSummary].
  final String title;

  /// When the meeting takes place.
  final Instant scheduledAt;

  /// Where the meeting takes place, trimmed by [createMeetingSummary].
  final String location;
}

/// Builds a summary. The title and the location are trimmed; neither may be
/// blank, and they must not be longer than [maxTitleLength] and 300.
Result<MeetingSummary, ValidationError> createMeetingSummary(
  MeetingSummaryInput input,
) => andThen(
  requireText(ValidationField.title, input.title, maxTitleLength),
  (title) => andThen(
    requireText(ValidationField.location, input.location, _maxLocationLength),
    (location) => ok(
      MeetingSummary(
        id: input.id,
        title: title,
        scheduledAt: input.scheduledAt,
        location: location,
      ),
    ),
  ),
);
