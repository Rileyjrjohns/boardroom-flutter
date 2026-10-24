import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/presentation/screens/meetings_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/builders/builders.dart';
import '../support/presentation/test_app.dart';
import 'support/golden_screen.dart';

// The meetings list in its main states, in English and in French, at the size
// of a phone: the list, an empty period, the list read from the copy saved on
// the device while offline, and the error of a first page that failed.

/// The meetings of the upcoming period: titles and rooms of a real board.
final List<MeetingSummary> _upcoming = [
  aMeetingSummary(
    id: aMeetingId('budget'),
    title: 'Budget committee',
    location: 'Room Ravel',
    scheduledAt: at(2 * millisPerDay),
  ),
  aMeetingSummary(
    id: aMeetingId('board'),
    location: 'Head office, Paris',
    scheduledAt: at(9 * millisPerDay),
  ),
  aMeetingSummary(
    id: aMeetingId('audit'),
    title: 'Audit committee',
    location: 'Video call',
    scheduledAt: at(23 * millisPerDay),
  ),
];

void _serve(TestApp app) =>
    app.fakes.meetings.setMeetings(MeetingPeriod.upcoming, _upcoming);

/// Reads the first page once, so that the device holds a copy of it, then
/// loses the network a day later.
Future<void> _saveThenGoOffline(TestApp app) async {
  _serve(app);
  app.fakes.auth.session = aSession(expiresAt: at(30 * millisPerDay));
  await app.useCases.listMeetings.execute(
    period: MeetingPeriod.upcoming,
    request: unwrap(createPageRequest(limit: 10)),
  );
  app.fakes.clock.advance(millisPerDay);
  app.fakes.network.goOffline();
}

void _failTheFirstPage(TestApp app) {
  _serve(app);
  app.fakes.meetings.failure = unexpected();
}

void _empty(TestApp app) =>
    app.fakes.meetings.setMeetings(MeetingPeriod.upcoming, const []);

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final code = locale.languageCode;
    screenGoldenTest(
      'the meetings list in $code',
      fileName: 'meetings_list_$code',
      scenarios: [
        goldenScenario(
          name: 'loaded',
          locale: locale,
          screen: MeetingsListScreen.new,
          prepare: _serve,
        ),
        goldenScenario(
          name: 'empty',
          locale: locale,
          screen: MeetingsListScreen.new,
          prepare: _empty,
        ),
        goldenScenario(
          name: 'saved copy, offline',
          locale: locale,
          screen: MeetingsListScreen.new,
          prepare: _saveThenGoOffline,
          deviceOffline: true,
        ),
        goldenScenario(
          name: 'error',
          locale: locale,
          screen: MeetingsListScreen.new,
          prepare: _failTheFirstPage,
        ),
      ],
    );
  }
}
