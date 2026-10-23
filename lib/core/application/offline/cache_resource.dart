import 'package:boardroom/core/domain/shared/constants.dart';

/// What is being cached, for the logs.
enum CacheResource implements StableValue {
  /// A page of the meeting list.
  meetingPage('meetingPage'),

  /// The detail of a meeting.
  meeting('meeting'),

  /// A document.
  document('document');

  new(this.value);

  @override
  final String value;
}
