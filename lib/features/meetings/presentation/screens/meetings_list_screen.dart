import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:flutter/widgets.dart';

/// The meetings list, the home of the open app (docs/spec/screens.md "Meetings
/// list").
///
/// A placeholder until the meetings agent writes the screen: the router mounts
/// this class with this constructor, so the file is replaced in place. A tap on
/// a row opens the meeting with `openMeeting(context, id)` of
/// `lib/core/presentation/navigation/navigate.dart`.
class MeetingsListScreen extends StatelessWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: Key(MeetingsTestIds.meetingsList));
}
