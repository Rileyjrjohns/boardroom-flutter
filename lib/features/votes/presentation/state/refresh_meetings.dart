import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/meetings/presentation/state/meeting_query.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The votes change what the meetings show: a recorded vote is carried by its
// resolution. The queries are the meetings', read through their providers.

/// One meeting: a vote was recorded on it, or refused. Reads it again and
/// settles when it has answered, so that a button stays busy until the screen
/// shows the outcome; a failure is told by the screen that reads the meeting.
Future<void> refreshMeeting(Ref ref, MeetingId meetingId) async {
  ref.invalidate(meetingQueryProvider(meetingId));
  try {
    await ref.read(meetingQueryProvider(meetingId).future);
  } on Object {
    // Told by the meeting screen.
  }
}

/// Every meeting held: a synchronisation recorded votes on some of them. The
/// ones a screen shows are read again, the others when a screen needs them.
Future<void> refreshMeetings(Ref ref) async =>
    ref.invalidate(meetingQueryProvider);
