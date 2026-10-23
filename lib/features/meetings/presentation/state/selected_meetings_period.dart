import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'selected_meetings_period.g.dart';

/// Which period of the meetings list is selected. It is state of the interface
/// that belongs to the meetings and nothing else: it is kept while a meeting
/// is open (the list stays below the detail) and when the user comes back to
/// the list, like the `meetingsStore` of the React Native app.
@Riverpod(keepAlive: true)
class SelectedMeetingsPeriod extends _$SelectedMeetingsPeriod {
  @override
  MeetingPeriod build() => MeetingPeriod.upcoming;

  /// Selects [period].
  // ignore: use_setters_to_change_properties
  void select(MeetingPeriod period) => state = period;
}
