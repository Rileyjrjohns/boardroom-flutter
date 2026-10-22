// The arguments restate the values of the scenario, even when they are the
// defaults of the builders.
// ignore_for_file: avoid_redundant_argument_values

import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/domain/entities/resolution.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/policies/voting_eligibility.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/domain/value_objects/vote_choice.dart';
import 'package:test/test.dart';

import '../support/builders.dart';
import '../support/names.dart';

/// A meeting whose only resolution is [resolution].
Meeting _meetingWith(Resolution resolution) =>
    aMeeting(agenda: [anAgendaItem(resolution: resolution)]);

VotingEligibilityInput _input({
  Meeting? meeting,
  ResolutionId? resolutionId,
  UserId? voterId,
  List<PendingVote> queuedVotes = const [],
  Instant? instant,
}) => VotingEligibilityInput(
  meeting: meeting ?? aMeeting(),
  resolutionId: resolutionId ?? aResolutionId(),
  voterId: voterId ?? aUserId(),
  queuedVotes: queuedVotes,
  now: instant ?? now,
);

void main() {
  group('checkVotingEligibility', () {
    test('accepts a member on an open resolution', () {
      expect(checkVotingEligibility(_input()), equals(ok<void>(null)));
    });

    test('accepts the chair', () {
      expect(
        checkVotingEligibility(_input(voterId: aUserId('user-2'))),
        equals(ok<void>(null)),
      );
    });

    test('rejects a resolution the meeting does not have', () {
      expect(
        checkVotingEligibility(_input(resolutionId: aResolutionId('missing'))),
        equals(
          err(ResolutionNotFoundError(resolutionId: aResolutionId('missing'))),
        ),
      );
    });

    test('rejects somebody who is not a participant', () {
      expect(
        checkVotingEligibility(_input(voterId: aUserId('stranger'))),
        equals(err(const NotAParticipantError())),
      );
    });

    for (final id in ['user-3', 'user-4']) {
      test('rejects the participant $id, who has no voting rights', () {
        expect(
          checkVotingEligibility(_input(voterId: aUserId(id))),
          equals(err(const NoVotingRightsError())),
        );
      });
    }

    test('rejects a closed resolution', () {
      final meeting = _meetingWith(
        aResolution(status: ResolutionStatus.closed),
      );

      expect(
        checkVotingEligibility(_input(meeting: meeting)),
        equals(err(const ResolutionClosedError())),
      );
    });

    test('accepts a vote until the voting window closes', () {
      final meeting = _meetingWith(aResolution(closesAt: at(1)));

      expect(
        checkVotingEligibility(_input(meeting: meeting)),
        equals(ok<void>(null)),
      );
    });

    for (final offset in [0, -1, -3600000]) {
      test('rejects a vote when the window closed ${formatPretty(offset)} '
          'ms from now, the closing instant included', () {
        final meeting = _meetingWith(aResolution(closesAt: at(offset)));

        expect(
          checkVotingEligibility(_input(meeting: meeting)),
          equals(err(const VotingWindowOverError())),
        );
      });
    }

    test('rejects a voter whose vote is already recorded', () {
      final meeting = _meetingWith(
        aResolution(recordedVote: VoteChoice.against),
      );

      expect(
        checkVotingEligibility(_input(meeting: meeting)),
        equals(
          err(const AlreadyVotedError(source: AlreadyVotedSource.recorded)),
        ),
      );
    });

    test('rejects a voter whose vote waits in the outbox', () {
      final queuedVotes = [aPendingVote(aVote())];

      expect(
        checkVotingEligibility(_input(queuedVotes: queuedVotes)),
        equals(err(const AlreadyVotedError(source: AlreadyVotedSource.queued))),
      );
    });

    test('ignores a queued vote of somebody else, '
        'and a queued vote on another resolution', () {
      final queuedVotes = [
        aPendingVote(aVote(voterId: aUserId('user-2'))),
        aPendingVote(aVote(resolutionId: aResolutionId('other'))),
      ];

      expect(
        checkVotingEligibility(_input(queuedVotes: queuedVotes)),
        equals(ok<void>(null)),
      );
    });

    group('a resolution that sits in a later item of the agenda', () {
      final resolution2 = aResolutionId('resolution-2');
      Meeting withAgenda(Resolution first, Resolution second) =>
          aMeetingWithAgenda(
            agenda: [
              anAgendaItem(
                id: anAgendaItemId('agenda-1'),
                position: 1,
                resolution: first,
              ),
              anAgendaItem(
                id: anAgendaItemId('agenda-2'),
                position: 2,
                resolution: second,
              ),
            ],
          );

      test('is found and accepted, for a member of the board', () {
        expect(
          checkVotingEligibility(
            _input(meeting: aMeetingWithAgenda(), resolutionId: resolution2),
          ),
          equals(ok<void>(null)),
        );
      });

      test(
        'is judged on its own state, not on the state of the first resolution',
        () {
          final meeting = withAgenda(
            aResolution(status: ResolutionStatus.closed),
            aResolution(id: resolution2),
          );

          expect(
            checkVotingEligibility(
              _input(meeting: meeting, resolutionId: resolution2),
            ),
            equals(ok<void>(null)),
          );
          expect(
            checkVotingEligibility(_input(meeting: meeting)),
            equals(err(const ResolutionClosedError())),
          );
        },
      );

      test('is refused when it is the one that is closed, '
          'and the first one is open', () {
        final meeting = withAgenda(
          aResolution(),
          aResolution(id: resolution2, status: ResolutionStatus.closed),
        );

        expect(
          checkVotingEligibility(
            _input(meeting: meeting, resolutionId: resolution2),
          ),
          equals(err(const ResolutionClosedError())),
        );
        expect(
          checkVotingEligibility(_input(meeting: meeting)),
          equals(ok<void>(null)),
        );
      });

      test('is refused when the vote recorded is the one of that resolution, '
          'not of the first', () {
        final meeting = withAgenda(
          aResolution(recordedVote: VoteChoice.forChoice),
          aResolution(id: resolution2),
        );

        expect(
          checkVotingEligibility(
            _input(meeting: meeting, resolutionId: resolution2),
          ),
          equals(ok<void>(null)),
        );
        expect(
          checkVotingEligibility(_input(meeting: meeting)),
          equals(
            err(const AlreadyVotedError(source: AlreadyVotedSource.recorded)),
          ),
        );
      });

      test(
        'is refused as not found when the id matches no resolution of any item',
        () {
          expect(
            checkVotingEligibility(
              _input(
                meeting: aMeetingWithAgenda(),
                resolutionId: aResolutionId('resolution-3'),
              ),
            ),
            equals(
              err(
                ResolutionNotFoundError(
                  resolutionId: aResolutionId('resolution-3'),
                ),
              ),
            ),
          );
        },
      );
    });

    group(
      'when several reasons apply at once, the earliest of the list wins',
      () {
        final closed = _meetingWith(
          aResolution(status: ResolutionStatus.closed),
        );
        final windowOver = _meetingWith(aResolution(closesAt: at(-1)));
        final everything = _meetingWith(
          aResolution(
            status: ResolutionStatus.closed,
            closesAt: at(-1),
            recordedVote: VoteChoice.forChoice,
          ),
        );
        final recorded = _meetingWith(
          aResolution(closesAt: at(-1), recordedVote: VoteChoice.forChoice),
        );
        final queuedVotes = [aPendingVote(aVote())];

        for (final (name, input, expected)
            in <(String, VotingEligibilityInput, VotingError)>[
              (
                '1 over 2: an unknown resolution and a stranger',
                _input(
                  resolutionId: aResolutionId('missing'),
                  voterId: aUserId('stranger'),
                ),
                ResolutionNotFoundError(resolutionId: aResolutionId('missing')),
              ),
              (
                '1 over 3: an unknown resolution and a guest',
                _input(
                  resolutionId: aResolutionId('missing'),
                  voterId: aUserId('user-4'),
                ),
                ResolutionNotFoundError(resolutionId: aResolutionId('missing')),
              ),
              (
                '1 over the rest: an unknown resolution, '
                    'in a meeting where everything else is wrong too',
                _input(
                  meeting: everything,
                  resolutionId: aResolutionId('missing'),
                  voterId: aUserId('user-4'),
                  queuedVotes: queuedVotes,
                ),
                ResolutionNotFoundError(resolutionId: aResolutionId('missing')),
              ),
              (
                '2 over 4: a stranger and a closed resolution',
                _input(meeting: closed, voterId: aUserId('stranger')),
                const NotAParticipantError(),
              ),
              (
                '3 over 4: a guest and a closed resolution',
                _input(meeting: closed, voterId: aUserId('user-4')),
                const NoVotingRightsError(),
              ),
              (
                '4 over 5: a closed resolution whose window is over',
                _input(meeting: everything),
                const ResolutionClosedError(),
              ),
              (
                '5 over 6: a window that is over, and a recorded vote',
                _input(meeting: recorded),
                const VotingWindowOverError(),
              ),
              (
                '5 over 6: a window that is over, and a queued vote',
                _input(meeting: windowOver, queuedVotes: queuedVotes),
                const VotingWindowOverError(),
              ),
              (
                '6 recorded over 6 queued: a vote both recorded and queued',
                _input(
                  meeting: _meetingWith(
                    aResolution(recordedVote: VoteChoice.against),
                  ),
                  queuedVotes: queuedVotes,
                ),
                const AlreadyVotedError(source: AlreadyVotedSource.recorded),
              ),
            ]) {
          test(name, () {
            expect(checkVotingEligibility(input), equals(err(expected)));
          });
        }

        // A voter who is not in the meeting has no role, so 2 (not a
        // participant) and 3 (no voting rights) cannot apply together: there is
        // no pair to order.
      },
    );
  });
}
