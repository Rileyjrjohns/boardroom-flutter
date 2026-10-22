import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:test/test.dart';

import '../support/builders.dart';

MeetingSummaryInput _valid({
  String title = 'Board',
  String location = 'Room 1',
}) => MeetingSummaryInput(
  id: aMeetingId(),
  title: title,
  scheduledAt: now,
  location: location,
);

void main() {
  group('createMeetingSummary', () {
    test('builds a summary with trimmed texts', () {
      expect(
        createMeetingSummary(_valid(title: ' Board ', location: ' Room 1 ')),
        equals(
          ok(
            MeetingSummary(
              id: aMeetingId(),
              title: 'Board',
              scheduledAt: now,
              location: 'Room 1',
            ),
          ),
        ),
      );
    });

    test('rejects a blank title, then a blank location', () {
      expect(
        createMeetingSummary(_valid(title: '', location: '')),
        equals(
          err(validationError(ValidationField.title, ValidationRule.required)),
        ),
      );
      expect(
        createMeetingSummary(_valid(location: ' ')),
        equals(
          err(
            validationError(ValidationField.location, ValidationRule.required),
          ),
        ),
      );
    });
  });
}
