import 'package:boardroom/app/dev/in_memory/fixtures/load_fixtures.dart';
import 'package:boardroom/app/dev/in_memory/in_memory_auth_session.dart';
import 'package:boardroom/app/dev/in_memory/in_memory_backend.dart';
import 'package:boardroom/app/dev/in_memory/seed.dart';
import 'package:boardroom/app/dev/in_memory/simulated_network.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/policies/voting_state.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/domain/policies/voting_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/fake_clock.dart';
import '../../../support/infrastructure/fixture_files.dart';
import '../../../support/infrastructure/sleep.dart';
import '../../../support/infrastructure/test_server.dart';

// The seed of the simulated server is the fixtures of docs/spec/fixtures,
// shifted to the clock. What matters to the app is what the shifted data looks
// like at any instant the app may start at: the invariants below hold at each
// of the instants listed, not only at the reference date of the files.
//
// The seed is built from the files on disk (`loadFixtures`, which `buildSeed`
// calls on the bundled copy of the same files): the first group checks that the
// two give the same data.

/// How many meetings of each period the fixtures hold: several pages of each at
/// the page sizes of the app.
const int _upcomingMeetingCount = 24;
const int _pastMeetingCount = 42;

Instant _instant(int millis) => unwrap(parseInstant(millis));

SeedData _seedAt([Instant? at]) {
  final seed = loadFixtures(readFixtureFiles(), at ?? now);
  return switch (seed) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError(
      'The seed is invalid: ${error.detail}',
    ),
  };
}

final int _reference = referenceDateOnDisk();

/// The instants the app may start at: the reference date of the files, around
/// it, and far from it.
final List<(String, int)> _startInstants = [
  ('the instant of the tests', now),
  ('a millisecond later', now + 1),
  ('the reference date of the files', _reference),
  ('a millisecond before the reference date', _reference - 1),
  ('a month before the reference date', _reference - 30 * millisPerDay),
  ('the start of a day', (now / millisPerDay).floor() * millisPerDay),
  (
    'the last millisecond of a day',
    (now / millisPerDay).ceil() * millisPerDay - 1,
  ),
  ('half a year later', now + 183 * millisPerDay),
  ('the year 2096', 4000000000000),
];

List<Resolution> _resolutionsOf(Meeting meeting) => [
  for (final item in meeting.agenda) ?item.resolution,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the seed of the simulated server, read from the fixtures', () {
    final seed = _seedAt();
    final content = seed.content;
    final accounts = seed.accounts;
    final alice = seed.demoUser;
    final bruno = accounts[1].user;
    final upcoming = content.meetings
        .where((meeting) => meeting.scheduledAt > now)
        .toList();
    final past = content.meetings
        .where((meeting) => meeting.scheduledAt <= now)
        .toList();

    for (final (name, millis) in _startInstants) {
      test('has the same upcoming and past meetings at $name, '
          'built through the domain factories', () {
        final at = _instant(millis);

        final meetings = _seedAt(at).content.meetings;

        expect(
          meetings.where((meeting) => meeting.scheduledAt > at),
          hasLength(_upcomingMeetingCount),
        );
        expect(
          meetings.where((meeting) => meeting.scheduledAt <= at),
          hasLength(_pastMeetingCount),
        );
      });
    }

    test('is invalid, and says so, when the instant leaves no room '
        'for the past meetings', () {
      final early = loadFixtures(readFixtureFiles(), _instant(1000));

      expect(early, isA<Err<SeedData, FixtureError>>());
      final error = (early as Err<SeedData, FixtureError>).error;
      expect(error.code, equals(FixtureErrorCode.invalidValue));
      expect(error.file, equals(FixtureFile.meetings));
      expect(error.detail, contains('meetings.json: meetings.'));
    });

    test(
      'depends on the clock alone: the same instant gives the same data',
      () {
        expect(_seedAt(), equals(_seedAt()));
      },
    );

    test('has both upcoming and past meetings, '
        'enough for several pages of each', () {
      expect(upcoming, hasLength(_upcomingMeetingCount));
      expect(past, hasLength(_pastMeetingCount));
      expect(upcoming.length, greaterThan(2 * 10));
      expect(past.length, greaterThan(2 * 10));
    });

    test('follows the clock: moving it moves every meeting with it', () {
      final later = _seedAt(_instant(now + millisPerDay));

      expect(
        later.content.meetings.where(
          (meeting) => meeting.scheduledAt > now + millisPerDay,
        ),
        hasLength(_upcomingMeetingCount),
      );
    });

    test('gives every meeting a distinct id, title, an agenda, '
        'documents and participants', () {
      final ids = content.meetings.map((meeting) => meeting.id).toList();
      final titles = content.meetings.map((meeting) => meeting.title).toList();

      expect(ids.toSet(), hasLength(ids.length));
      expect(titles.toSet(), hasLength(titles.length));
      for (final meeting in content.meetings) {
        expect(meeting.agenda, isNotEmpty);
        expect(meeting.documents, isNotEmpty);
        expect(meeting.participants, isNotEmpty);
        expect(meeting.location, isNot(equals('')));
      }
    });

    test('declares two demo accounts that share the demo password, '
        'the first one being the demo user', () {
      expect(accounts, hasLength(2));
      expect(
        accounts.map((account) => account.password),
        equals([demoPassword, demoPassword]),
      );
      expect(accounts[0].user, equals(alice));
      expect(alice.email, isNot(equals(bruno.email)));
    });

    test('has the demo user as a voting member of most meetings, '
        'and as a non-voting guest in some', () {
      final roles = content.meetings
          .map((meeting) => findParticipant(meeting, alice.id)?.role)
          .toList();
      final voting = content.meetings.where((meeting) {
        final seat = findParticipant(meeting, alice.id);
        return seat != null && hasVotingRights(seat);
      });

      expect(voting.length, greaterThan(content.meetings.length / 2));
      expect(roles, contains(ParticipantRole.guest));
      expect(roles, contains(ParticipantRole.secretary));
      expect(roles, contains(ParticipantRole.chair));
      expect(roles, contains(ParticipantRole.member));
    });

    test('has the demo user in every meeting '
        'and the second demo user in some only', () {
      expect(
        content.meetings.every(
          (meeting) => findParticipant(meeting, alice.id) != null,
        ),
        isTrue,
      );
      final withBruno = content.meetings.where(
        (meeting) => findParticipant(meeting, bruno.id) != null,
      );

      expect(withBruno.length, greaterThan(0));
      expect(withBruno.length, lessThan(content.meetings.length));
    });

    test('has every kind of resolution: open, open without a closing time, '
        'closed with a closing time', () {
      final resolutions = content.meetings.expand(_resolutionsOf).toList();

      expect(
        resolutions.any(
          (r) => r.status == ResolutionStatus.open && r.closesAt != null,
        ),
        isTrue,
      );
      expect(
        resolutions.any(
          (r) => r.status == ResolutionStatus.open && r.closesAt == null,
        ),
        isTrue,
      );
      expect(
        resolutions.any(
          (r) => r.status == ResolutionStatus.closed && r.closesAt != null,
        ),
        isTrue,
      );
    });

    test('keeps recorded votes out of the meetings: '
        'they belong to their voter', () {
      expect(
        content.meetings
            .expand(_resolutionsOf)
            .every((r) => r.recordedVote == null),
        isTrue,
      );
    });

    test('has an open resolution of an upcoming meeting '
        'that the demo user already voted on', () {
      final open = upcoming
          .expand(_resolutionsOf)
          .where((r) => r.status == ResolutionStatus.open)
          .map((r) => r.id)
          .toSet();

      expect(
        content.recordedVotes.any(
          (vote) =>
              vote.voterId == alice.id && open.contains(vote.resolutionId),
        ),
        isTrue,
      );
    });

    test('records only votes on resolutions that exist, '
        'of voters who may vote there, once each', () {
      final meetingOf = {
        for (final meeting in content.meetings)
          for (final resolution in _resolutionsOf(meeting))
            resolution.id: meeting,
      };

      for (final vote in content.recordedVotes) {
        final meeting = meetingOf[vote.resolutionId];
        final seat = meeting == null
            ? null
            : findParticipant(meeting, vote.voterId);
        expect(meeting?.id, equals(vote.meetingId));
        expect(seat != null && hasVotingRights(seat), isTrue);
      }
      final keys = content.recordedVotes.map((vote) => vote.idempotencyKey);
      expect(keys.toSet(), hasLength(keys.length));
    });

    for (final (name, millis) in _startInstants) {
      group('the resolutions at $name', () {
        final at = _instant(millis);
        final seed = _seedAt(at);
        final meetings = seed.content.meetings;
        bool isUpcoming(Meeting meeting) => meeting.scheduledAt > at;
        final upcomingMeetings = meetings.where(isUpcoming).toList();
        final pastMeetings = meetings
            .where((meeting) => !isUpcoming(meeting))
            .toList();
        final demoUser = seed.demoUser;
        final demoVotes = seed.content.recordedVotes
            .where((vote) => vote.voterId == demoUser.id)
            .toList();

        test('are all open in an upcoming meeting, never closed, '
            'with a closing time after it starts or none', () {
          for (final meeting in upcomingMeetings) {
            for (final resolution in _resolutionsOf(meeting)) {
              expect(resolution.status, equals(ResolutionStatus.open));
              expect(getVotingState(resolution, at), equals(VotingState.open));
              final closesAt = resolution.closesAt;
              if (closesAt != null) {
                expect(closesAt, greaterThan(meeting.scheduledAt));
              }
            }
          }
        });

        test('have a closing time after the meeting started, '
            'and already behind, in a past meeting', () {
          for (final meeting in pastMeetings) {
            for (final resolution in _resolutionsOf(meeting)) {
              expect(resolution.closesAt, isNotNull);
              expect(resolution.closesAt, greaterThan(meeting.scheduledAt));
              expect(resolution.closesAt, lessThanOrEqualTo(at));
              expect(
                getVotingState(resolution, at),
                isNot(equals(VotingState.open)),
              );
            }
          }
        });

        test('close every close instant after its meeting starts, '
            'wherever it is', () {
          for (final meeting in meetings) {
            for (final resolution in _resolutionsOf(meeting)) {
              final closesAt = resolution.closesAt;
              if (closesAt != null) {
                expect(closesAt, greaterThan(meeting.scheduledAt));
              }
            }
          }
        });

        test('show every state of the voting somewhere, '
            'and the window over only in the past', () {
          Set<VotingState> states(List<Meeting> list) => list
              .expand(_resolutionsOf)
              .map((resolution) => getVotingState(resolution, at))
              .toSet();

          expect(states(meetings), equals(VotingState.values.toSet()));
          expect(states(upcomingMeetings), equals({VotingState.open}));
          expect(states(pastMeetings), contains(VotingState.closed));
          expect(states(pastMeetings), contains(VotingState.windowOver));
        });

        test('include a past resolution that is still open by status '
            'once its window is over', () {
          final lapsed = pastMeetings
              .expand(_resolutionsOf)
              .where((resolution) => resolution.status == ResolutionStatus.open)
              .toList();

          expect(lapsed, isNotEmpty);
          expect(
            lapsed.every(
              (resolution) =>
                  getVotingState(resolution, at) == VotingState.windowOver,
            ),
            isTrue,
          );
        });

        test('include upcoming resolutions with a closing time '
            'and upcoming ones without', () {
          final resolutions = upcomingMeetings.expand(_resolutionsOf).toList();

          expect(resolutions.any((r) => r.closesAt != null), isTrue);
          expect(resolutions.any((r) => r.closesAt == null), isTrue);
        });

        test('have every choice among the votes of the demo user, '
            'on closed resolutions', () {
          final closed = pastMeetings
              .expand(_resolutionsOf)
              .where(
                (resolution) =>
                    getVotingState(resolution, at) == VotingState.closed,
              )
              .map((resolution) => resolution.id)
              .toSet();
          final choices = demoVotes
              .where((vote) => closed.contains(vote.resolutionId))
              .map((vote) => vote.choice)
              .toSet();

          expect(choices, equals(VoteChoice.values.toSet()));
        });

        test('have closed resolutions the demo user voted on and closed ones '
            'they did not, as a voting member', () {
          final voted = demoVotes.map((vote) => vote.resolutionId).toSet();
          final closedAsVoter = pastMeetings
              .where((meeting) {
                final seat = findParticipant(meeting, demoUser.id);
                return seat != null && hasVotingRights(seat);
              })
              .expand(_resolutionsOf)
              .where(
                (resolution) =>
                    getVotingState(resolution, at) == VotingState.closed,
              )
              .toList();

          expect(
            closedAsVoter.any((resolution) => voted.contains(resolution.id)),
            isTrue,
          );
          expect(
            closedAsVoter.any((resolution) => !voted.contains(resolution.id)),
            isTrue,
          );
        });

        test('leave a few upcoming resolutions '
            'that the demo user can vote on right away', () {
          final voted = demoVotes.map((vote) => vote.resolutionId).toSet();
          final votable = upcomingMeetings.where(
            (meeting) => _resolutionsOf(meeting).any(
              (resolution) =>
                  !voted.contains(resolution.id) &&
                  checkVotingEligibility(
                    VotingEligibilityInput(
                      meeting: meeting,
                      resolutionId: resolution.id,
                      voterId: demoUser.id,
                      queuedVotes: const [],
                      now: at,
                    ),
                  ) is Ok,
            ),
          );

          expect(votable.length, greaterThanOrEqualTo(3));
        });

        test('have the demo user as a guest in a meeting, '
            'where there is nothing for them to vote on', () {
          final asGuest = meetings.where(
            (meeting) =>
                findParticipant(meeting, demoUser.id)?.role ==
                ParticipantRole.guest,
          );

          expect(asGuest, isNotEmpty);
          for (final meeting in asGuest) {
            for (final resolution in _resolutionsOf(meeting)) {
              final eligibility = checkVotingEligibility(
                VotingEligibilityInput(
                  meeting: meeting,
                  resolutionId: resolution.id,
                  voterId: demoUser.id,
                  queuedVotes: const [],
                  now: at,
                ),
              );
              expect(
                (eligibility as Err<void, VotingError>).error.code,
                equals(VotingErrorCode.noVotingRights.value),
              );
            }
          }
        });

        test('have no vote of the demo user on a resolution '
            'whose window lapsed', () {
          final lapsed = pastMeetings
              .expand(_resolutionsOf)
              .where((resolution) => resolution.status == ResolutionStatus.open)
              .map((resolution) => resolution.id)
              .toSet();

          expect(
            seed.content.recordedVotes.any(
              (vote) => lapsed.contains(vote.resolutionId),
            ),
            isFalse,
          );
        });
      });
    }

    test('has documents that are confidential and documents that are not', () {
      final levels = content.meetings
          .expand((meeting) => meeting.documents)
          .map((document) => document.confidentiality)
          .toSet();

      expect(levels, contains(ConfidentialityLevel.confidential));
      expect(levels, contains(ConfidentialityLevel.internal));
      expect(levels, contains(ConfidentialityLevel.public));
    });

    test('has distinct document ids across meetings, '
        'so that a document belongs to one meeting', () {
      final ids = content.meetings
          .expand((meeting) => meeting.documents)
          .map((document) => document.id)
          .toList();

      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  group('the fixtures of docs/spec/fixtures', () {
    test('give the demo accounts the password the app documents', () async {
      final seed = await buildSeed(now);

      expect(
        (seed as Ok<SeedData, SeedError>).value.accounts.map(
          (account) => account.password,
        ),
        equals([demoPassword, demoPassword]),
      );
    });
  });

  group('the simulated server holding the fixtures', () {
    test('serves to each demo user the meetings they take part in, '
        'soonest first, shifted to the clock', () async {
      final seed = unwrap(await buildSeed(now));
      final clock = FakeClock(now);
      final network = SimulatedNetwork(
        sleep: immediateSleep,
        latency: aDuration(0),
      );
      final auth = InMemoryAuthSession(
        clock: clock,
        network: network,
        accounts: seed.accounts,
        sessionLifetime: testSessionLifetime,
      )..openSessionFor(seed.demoUser);
      final backend = unwrap(
        InMemoryBackend.create(
          InMemoryBackendOptions(
            clock: clock,
            auth: AuthSessionCaller(auth),
            network: network,
            content: seed.content,
          ),
        ),
      );

      final upcoming = unwrap(
        await backend.listMeetings(
          MeetingPeriod.upcoming,
          const PageRequest(limit: 50),
        ),
      );
      final past = unwrap(
        await backend.listMeetings(
          MeetingPeriod.past,
          const PageRequest(limit: 50),
        ),
      );

      expect(upcoming.items, hasLength(24));
      final times = upcoming.items.map((item) => item.scheduledAt).toList();
      expect(times, equals([...times]..sort()));
      expect(upcoming.items.first.id, equals('meeting-001'));
      expect(upcoming.items.every((item) => item.scheduledAt > now), isTrue);
      expect(past.items.every((item) => item.scheduledAt <= now), isTrue);
      expect(upcoming.items.length + past.items.length, lessThanOrEqualTo(66));
      final meeting = unwrap(await backend.getMeeting(upcoming.items.first.id));
      expect(
        meeting.agenda.any((item) => item.resolution?.recordedVote != null),
        isTrue,
      );
    });
  });

  group('the seed, in Dart', () {
    test('is the one the fixtures bundled with the app make', () async {
      expect(await buildSeed(now), equals(ok(_seedAt())));
    });

    test('is the same data for the same instant, through the bundle', () async {
      expect(await buildSeed(now), equals(await buildSeed(now)));
    });
  });
}
