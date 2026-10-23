import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/policies/voting_state.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/infrastructure/in_memory/fixtures/load_fixtures.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import '../../support/fixture_files.dart';

// The fixtures are shifted by a whole number of days, so that the meetings keep
// their time of day. What the app relies on is that the shift never moves a
// meeting, or the end of a voting window, from one side of the clock to the
// other: whatever the instant the app starts at, the same 24 meetings are ahead
// and the same 42 behind, and every resolution is in the same voting state as
// at the reference date. These tests load the files at instants spread over a
// day (the hour at which the shift changes, the hours around it, midnight UTC)
// and over the years, and compare.

const int _millisPerHour = 3600000;
const int _millisPerMinute = 60000;
const int _millisPerDay = 24 * _millisPerHour;
const int _upcomingMeetingCount = 24;
const int _pastMeetingCount = 42;

final int _reference = referenceDateOnDisk();

int _utc(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
  int second = 0,
  int millisecond = 0,
]) => DateTime.utc(
  year,
  month,
  day,
  hour,
  minute,
  second,
  millisecond,
).millisecondsSinceEpoch;

/// Midnight UTC of an arbitrary day, the one whose hours are listed below.
final int _aMidnight = _utc(2027, 3, 14);

/// Where the reference date falls in its day: the shift changes by a day at
/// that time of day, every day.
final int _shiftTimeOfDay =
    ((_reference % _millisPerDay) + _millisPerDay) % _millisPerDay;

String _pad(int value) => value.toString().padLeft(2, '0');

final List<(String, int)> _everyHourOfADay = [
  for (var hour = 0; hour < 24; hour++)
    ('${_pad(hour)}:00 UTC', _aMidnight + hour * _millisPerHour),
];

final List<(String, int)> _aroundMidnight = [
  ('the minute before midnight UTC', _aMidnight - _millisPerMinute),
  ('the last millisecond before midnight UTC', _aMidnight - 1),
  ('midnight UTC', _aMidnight),
  ('the minute after midnight UTC', _aMidnight + _millisPerMinute),
];

final List<(String, int)> _aroundTheShift = [
  (
    'the minute before the shift changes',
    _aMidnight + _shiftTimeOfDay - _millisPerMinute,
  ),
  (
    'the last millisecond before the shift changes',
    _aMidnight + _shiftTimeOfDay - 1,
  ),
  ('the instant the shift changes', _aMidnight + _shiftTimeOfDay),
  (
    'the minute after the shift changes',
    _aMidnight + _shiftTimeOfDay + _millisPerMinute,
  ),
];

final List<(String, int)> _acrossTheYears = [
  for (final year in [
    1990,
    2000,
    2024,
    2026,
    2027,
    2028,
    2031,
    2050,
    2100,
    2200,
  ]) ...[
    ('the first instant of $year', _utc(year, 1, 1)),
    ('a day in the middle of $year', _utc(year, 6, 15, 12, 34, 56, 789)),
    ('the last millisecond of $year', _utc(year + 1, 1, 1) - 1),
  ],
];

final List<(String, int)> _instants = [
  ..._everyHourOfADay,
  ..._aroundMidnight,
  ..._aroundTheShift,
  ..._acrossTheYears,
];

Instant _instant(int millis) => unwrap(parseInstant(millis));

SeedData _loadedAt(int millis) {
  final loaded = loadFixtures(readFixtureFiles(), _instant(millis));
  return switch (loaded) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError(error.detail),
  };
}

typedef _Timeline = ({
  List<Meeting> meetings,
  List<String> upcomingIds,
  List<String> pastIds,
  Map<String, VotingState> states,
  int latestCastAt,
});

/// Which meetings are upcoming, and the voting state of each resolution, at
/// `millis`.
_Timeline _timelineAt(int millis) {
  final at = _instant(millis);
  final content = _loadedAt(millis).content;
  bool upcoming(Meeting meeting) => meeting.scheduledAt > at;
  final states = <String, VotingState>{
    for (final meeting in content.meetings)
      for (final item in meeting.agenda)
        if (item.resolution case final resolution?)
          resolution.id: getVotingState(resolution, at),
  };
  return (
    meetings: content.meetings,
    upcomingIds: [
      for (final meeting in content.meetings)
        if (upcoming(meeting)) meeting.id,
    ],
    pastIds: [
      for (final meeting in content.meetings)
        if (!upcoming(meeting)) meeting.id,
    ],
    states: states,
    latestCastAt: content.recordedVotes
        .map((vote) => vote.castAt as int)
        .reduce((a, b) => a > b ? a : b),
  );
}

void main() {
  group('the timeline of the fixtures', () {
    final atReference = _timelineAt(_reference);
    final written = atReference.meetings;

    test('is, at the reference date, 24 meetings ahead and 42 '
        'behind, the ahead ones all open', () {
      expect(atReference.upcomingIds, hasLength(_upcomingMeetingCount));
      expect(atReference.pastIds, hasLength(_pastMeetingCount));
      final upcoming = atReference.upcomingIds.toSet();
      for (final meeting in atReference.meetings) {
        for (final item in meeting.agenda) {
          final resolution = item.resolution;
          if (resolution == null) {
            continue;
          }
          if (upcoming.contains(meeting.id)) {
            expect(atReference.states[resolution.id], equals(VotingState.open));
          }
        }
      }
      expect(
        atReference.states.values.toSet(),
        equals(VotingState.values.toSet()),
      );
    });

    for (final (name, millis) in _instants) {
      group('at $name', () {
        final timeline = _timelineAt(millis);

        test('has the same meetings ahead and behind as at the '
            'reference date: 24 and 42', () {
          expect(timeline.upcomingIds, equals(atReference.upcomingIds));
          expect(timeline.pastIds, equals(atReference.pastIds));
          expect(timeline.upcomingIds, hasLength(_upcomingMeetingCount));
          expect(timeline.pastIds, hasLength(_pastMeetingCount));
        });

        test('has every resolution in the voting state it has at the '
            'reference date', () {
          expect(timeline.states, equals(atReference.states));
        });

        test('has no vote cast in the future', () {
          expect(timeline.latestCastAt, lessThanOrEqualTo(millis));
        });

        test('keeps the hour of every meeting and of every closing '
            'time: a whole number of days apart', () {
          final shifted = _loadedAt(millis).content.meetings;
          for (final (index, meeting) in shifted.indexed) {
            final original = written[index];
            final days =
                (meeting.scheduledAt - original.scheduledAt) / _millisPerDay;
            expect(days, equals(days.truncate()));
            expect(meeting.scheduledAt % _millisPerHour, equals(0));
            for (final item in meeting.agenda) {
              final closesAt = item.resolution?.closesAt;
              if (closesAt != null) {
                expect(closesAt % _millisPerHour, equals(0));
              }
            }
          }
        });
      });
    }

    test('holds every quarter of an hour over three days around the '
        'reference date', () {
      const quarter = 15 * _millisPerMinute;
      final first = _reference - _millisPerDay;
      final last = _reference + 2 * _millisPerDay;
      var checked = 0;

      for (var millis = first; millis <= last; millis += quarter) {
        final timeline = _timelineAt(millis);
        expect(timeline.upcomingIds, equals(atReference.upcomingIds));
        expect(timeline.pastIds, equals(atReference.pastIds));
        expect(timeline.states, equals(atReference.states));
        checked += 1;
      }

      expect(checked, equals(3 * 24 * 4 + 1));
    });
  });
}
