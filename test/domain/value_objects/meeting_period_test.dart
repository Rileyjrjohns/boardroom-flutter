import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/meeting_period.dart';
import 'package:test/test.dart';

void main() {
  group('MeetingPeriod', () {
    for (final period in MeetingPeriod.values) {
      test('parses ${period.value}', () {
        expect(parseMeetingPeriod(period.value), equals(ok(period)));
      });
    }

    test('rejects anything else', () {
      expect(
        parseMeetingPeriod('future'),
        equals(
          err(
            validationError(
              ValidationField.meetingPeriod,
              ValidationRule.unknownValue,
            ),
          ),
        ),
      );
    });
  });
}
