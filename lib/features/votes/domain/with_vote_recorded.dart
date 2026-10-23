import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';

/// A copy of the meeting in which the vote is recorded on its resolution, as
/// the server records it once the vote is accepted. Used to keep a cached copy
/// truthful, so that the voter cannot vote again from it. The meeting is
/// returned unchanged when the vote belongs to another meeting or to a
/// resolution it does not have.
///
/// It is the votes that know what a recorded vote does to a meeting, and the
/// meeting that knows nothing of votes (a resolution only records a choice), so
/// the function lives here and not with the meeting.
Meeting withVoteRecorded(Meeting meeting, Vote vote) {
  if (vote.meetingId != meeting.id) {
    return meeting;
  }
  return meeting.copyWith(
    agenda: [
      for (final item in meeting.agenda)
        if (item.resolution case final resolution?
            when resolution.id == vote.resolutionId)
          item.copyWith(
            resolution: resolution.copyWith(recordedVote: vote.choice),
          )
        else
          item,
    ],
  );
}
