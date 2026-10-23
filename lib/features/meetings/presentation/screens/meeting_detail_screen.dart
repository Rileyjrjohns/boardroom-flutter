import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:flutter/widgets.dart';

/// The detail of a meeting (docs/spec/screens.md "Meeting detail").
///
/// A placeholder until the meetings agent writes the screen: the router mounts
/// this class with this constructor, so the file is replaced in place.
/// [meetingId] is the raw path parameter: the screen parses it with
/// `parseMeetingId` and shows "not found" for one it refuses.
class MeetingDetailScreen extends StatelessWidget {
  /// Creates the screen for the meeting with the raw id [meetingId].
  const new({required this.meetingId, super.key});

  /// The raw `meetingId` path parameter.
  final String meetingId;

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: Key(MeetingsTestIds.meetingDetail));
}
