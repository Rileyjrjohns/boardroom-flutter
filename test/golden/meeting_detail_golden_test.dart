import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/features/meetings/domain/entities/agenda_item.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/meetings/presentation/screens/meeting_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/builders/builders.dart';
import '../support/presentation/test_app.dart';
import 'support/golden_screen.dart';

// The meeting detail in its main states, in English and in French, at the width
// of a phone and tall enough to show the whole page: the meeting with the vote
// block under each resolution (a vote to cast, a vote already recorded, a
// closed resolution), the meeting read from the copy saved on the device while
// offline, and the error of a meeting that cannot be shown.

final Meeting _meeting = aMeeting(
  summary: aMeetingSummary(
    id: aMeetingId('board'),
    location: 'Head office, Paris',
    scheduledAt: at(2 * millisPerDay),
  ),
  agenda: [
    unwrap(
      createAgendaItem(
        AgendaItemInput(
          id: anAgendaItemId('opening'),
          position: 1,
          title: 'Opening',
          description: 'Welcome and apologies.',
        ),
      ),
    ),
    anAgendaItem(
      id: anAgendaItemId('budget'),
      position: 2,
      resolution: aResolution(
        id: aResolutionId('budget-vote'),
        closesAt: at(millisPerDay),
        recordedVote: VoteChoice.against,
      ),
    ),
    anAgendaItem(
      id: anAgendaItemId('elections'),
      position: 3,
      title: 'Elections',
      resolution: aResolution(
        id: aResolutionId('elections-vote'),
        title: 'Elect the chair',
        description: 'Elect the chair of the board for two years.',
        closesAt: at(millisPerDay),
      ),
    ),
    anAgendaItem(
      id: anAgendaItemId('dividend'),
      position: 4,
      title: 'Dividend',
      resolution: aResolution(
        id: aResolutionId('dividend-vote'),
        title: 'Pay the dividend',
        status: ResolutionStatus.closed,
      ),
    ),
  ],
  documents: [
    aConfidentialDocument(
      id: aDocumentId('report'),
      title: 'Remuneration report',
      pageCount: 12,
    ),
    aDocument(id: aDocumentId('pack'), title: 'Board pack', pageCount: 1),
  ],
  participants: [
    aParticipant(fullName: 'Alice Martin'),
    aParticipant(
      userId: aUserId('user-2'),
      fullName: 'Bruno Durand',
      role: ParticipantRole.chair,
    ),
    aParticipant(
      userId: aUserId('user-4'),
      fullName: 'David Roux',
      role: ParticipantRole.guest,
    ),
  ],
);

Widget _screen() => MeetingDetailScreen(meetingId: _meeting.id);

void _serve(TestApp app) => app.fakes.meetings.addMeeting(_meeting);

Future<void> _saveThenGoOffline(TestApp app) async {
  app.fakes.auth.session = aSession(expiresAt: at(30 * millisPerDay));
  await app.fakes.meetingCache.saveMeeting(aUserId(), _meeting, now);
  app.fakes.clock.advance(millisPerDay ~/ 2);
  app.fakes.network.goOffline();
}

void _forbid(TestApp app) {
  _serve(app);
  app.fakes.meetings.failure = unexpected();
}

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final code = locale.languageCode;
    screenGoldenTest(
      'the meeting detail in $code',
      fileName: 'meeting_detail_$code',
      scenarios: [
        goldenScenario(
          name: 'loaded, with the votes',
          locale: locale,
          height: tallPhoneHeight,
          screen: _screen,
          prepare: _serve,
        ),
        goldenScenario(
          name: 'saved copy, offline',
          locale: locale,
          height: tallPhoneHeight,
          screen: _screen,
          prepare: _saveThenGoOffline,
          deviceOffline: true,
        ),
        goldenScenario(
          name: 'error',
          locale: locale,
          height: tallPhoneHeight,
          screen: _screen,
          prepare: _forbid,
        ),
      ],
    );
  }
}
