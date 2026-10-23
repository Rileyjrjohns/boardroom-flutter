import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';

/// The two lists of meetings. Which one a meeting belongs to depends on the
/// current instant.
enum MeetingPeriod implements StableValue {
  /// The meetings that have not happened yet.
  upcoming('upcoming'),

  /// The meetings that have happened.
  past('past');

  new(this.value);

  @override
  final String value;
}

/// Parses the stable string [raw] into a [MeetingPeriod].
Result<MeetingPeriod, ValidationError> parseMeetingPeriod(String raw) {
  final period = findConstant(MeetingPeriod.values, raw);
  return period == null
      ? err(
          validationError(
            ValidationField.meetingPeriod,
            ValidationRule.unknownValue,
          ),
        )
      : ok(period);
}
