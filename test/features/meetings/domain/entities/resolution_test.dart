import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';

ResolutionInput _valid({
  String title = 'Approve the budget',
  String description = 'Approve the budget of the next financial year.',
  Instant? closesAt,
  VoteChoice? recordedVote,
}) => ResolutionInput(
  id: aResolutionId(),
  title: title,
  description: description,
  status: ResolutionStatus.open,
  closesAt: closesAt,
  recordedVote: recordedVote,
);

void main() {
  group('createResolution', () {
    test('builds a resolution without closing instant nor recorded vote', () {
      final resolution = unwrap(createResolution(_valid()));

      expect(
        resolution,
        equals(
          Resolution(
            id: aResolutionId(),
            title: 'Approve the budget',
            description: 'Approve the budget of the next financial year.',
            status: ResolutionStatus.open,
          ),
        ),
      );
      expect(resolution.closesAt, isNull);
      expect(resolution.recordedVote, isNull);
    });

    test('keeps the closing instant and the recorded vote when given', () {
      expect(
        createResolution(
          _valid(closesAt: now, recordedVote: VoteChoice.abstain),
        ),
        equals(
          ok(
            Resolution(
              id: aResolutionId(),
              title: 'Approve the budget',
              description: 'Approve the budget of the next financial year.',
              status: ResolutionStatus.open,
              closesAt: now,
              recordedVote: VoteChoice.abstain,
            ),
          ),
        ),
      );
    });

    test('trims the texts', () {
      expect(
        createResolution(_valid(title: ' T ', description: ' D ')),
        equals(
          ok(
            Resolution(
              id: aResolutionId(),
              title: 'T',
              description: 'D',
              status: ResolutionStatus.open,
            ),
          ),
        ),
      );
    });

    test('rejects a blank title, then a blank description', () {
      expect(
        createResolution(_valid(title: ' ', description: ' ')),
        equals(
          err(validationError(ValidationField.title, ValidationRule.required)),
        ),
      );
      expect(
        createResolution(_valid(description: ' ')),
        equals(
          err(
            validationError(
              ValidationField.description,
              ValidationRule.required,
            ),
          ),
        ),
      );
    });
  });

  group('parseResolutionStatus', () {
    for (final status in ResolutionStatus.values) {
      test('parses ${status.value}', () {
        expect(parseResolutionStatus(status.value), equals(ok(status)));
      });
    }

    test('rejects an unknown status', () {
      expect(
        parseResolutionStatus('draft'),
        equals(
          err(
            validationError(
              ValidationField.resolutionStatus,
              ValidationRule.unknownValue,
            ),
          ),
        ),
      );
    });
  });
}
