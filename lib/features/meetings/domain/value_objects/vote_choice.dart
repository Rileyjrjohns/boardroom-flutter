import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';

/// What a voter answers to a resolution.
enum VoteChoice implements StableValue {
  /// In favour. (`for` is a reserved word of Dart; the stable string is `for`.)
  forChoice('for'),

  /// Against.
  against('against'),

  /// Neither for nor against.
  abstain('abstain');

  new(this.value);

  @override
  final String value;
}

/// Parses the stable string [raw] into a [VoteChoice].
Result<VoteChoice, ValidationError> parseVoteChoice(String raw) {
  final choice = findConstant(VoteChoice.values, raw);
  return choice == null
      ? err(
          validationError(
            ValidationField.voteChoice,
            ValidationRule.unknownValue,
          ),
        )
      : ok(choice);
}
