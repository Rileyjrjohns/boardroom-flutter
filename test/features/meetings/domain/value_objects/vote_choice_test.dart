import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:test/test.dart';

import '../../../../support/builders/names.dart';

void main() {
  group('VoteChoice', () {
    test('has three choices', () {
      expect(
        valuesOf(VoteChoice.values),
        equals(['for', 'against', 'abstain']),
      );
    });

    for (final choice in VoteChoice.values) {
      test('parses ${choice.value}', () {
        expect(parseVoteChoice(choice.value), equals(ok(choice)));
      });
    }

    for (final raw in [
      '',
      'FOR',
      'yes',
      ' for',
      'forward',
      'fo',
      'against!',
      'abstainer',
    ]) {
      test('rejects ${formatJson(raw)}', () {
        expect(
          parseVoteChoice(raw),
          equals(
            err(
              validationError(
                ValidationField.voteChoice,
                ValidationRule.unknownValue,
              ),
            ),
          ),
        );
      });
    }
  });
}
