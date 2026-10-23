import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/votes/application/ports/vote_outbox.dart';
import 'package:test/test.dart';

import '../builders/builders.dart';
import 'create_fakes.dart';

void main() {
  group('the fake meeting repository, in Dart', () {
    test(
      'keeps the order of the meetings that are scheduled together',
      () async {
        final fakes = createFakes();
        // `List.sort` of Dart is not stable: the fake breaks the tie itself, as
        // the sort of a list in JavaScript does.
        final summaries = [
          for (var index = 0; index < 40; index++)
            aMeetingSummary(id: aMeetingId('m$index')),
        ];
        fakes.meetings.setMeetings(MeetingPeriod.upcoming, summaries);

        final result = await fakes.meetings.list(
          MeetingPeriod.upcoming,
          const PageRequest(limit: 50),
        );

        final listed = <MeetingSummary>[...unwrap(result).items];
        expect(listed, equals(summaries));
      },
    );
  });

  group('EnqueueResult', () {
    test('tells its outcome as a stable value', () {
      expect(
        const EnqueueResult.enqueued().outcome,
        equals(EnqueueOutcome.enqueued),
      );
      expect(
        EnqueueResult.alreadyQueued(existing: aPendingVote()).outcome,
        equals(EnqueueOutcome.alreadyQueued),
      );
      expect(
        const EnqueueResult.heldByUnreadable().outcome,
        equals(EnqueueOutcome.heldByUnreadable),
      );
    });
  });
}
