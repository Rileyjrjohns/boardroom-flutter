import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/use_cases/list_pending_votes.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/presentation/state/resolution_vote.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders/builders.dart';

// What the screen says about a vote is the eligibility rule of the domain,
// ordered by what the user most needs to know. The rule itself is tested with
// the domain; these tests check that it is the one that is asked, for every
// reason, and how the outbox changes what is said.

const OutboxContent _emptyOutbox = OutboxContent(
  pending: [],
  rejected: [],
  unreadable: 0,
);

final Resolution _resolution = aResolution();
final Meeting _openMeeting = aMeeting(
  agenda: [anAgendaItem(resolution: _resolution)],
);

ResolutionVoteView _view({
  Meeting? meeting,
  Resolution? resolution,
  UserId? voterId,
  OutboxContent outbox = _emptyOutbox,
  Instant? at,
}) => resolutionVoteView(
  ResolutionVoteInput(
    meeting: meeting ?? _openMeeting,
    resolution: resolution ?? _resolution,
    voterId: voterId ?? aUserId(),
    outbox: outbox,
    now: at ?? now,
  ),
);

Meeting _meetingWith(Resolution resolution) =>
    aMeeting(agenda: [anAgendaItem(resolution: resolution)]);

OutboxContent _outbox({
  List<PendingVote> pending = const [],
  List<RejectedVote> rejected = const [],
}) => OutboxContent(pending: pending, rejected: rejected, unreadable: 0);

void main() {
  group('resolutionVoteView', () {
    test('lets a voting member vote on an open resolution nobody voted on', () {
      expect(_view(), isA<VoteViewEligible>());
    });

    for (final (who, userId, role) in [
      ('a secretary', 'user-3', ParticipantRole.secretary),
      ('a guest', 'user-4', ParticipantRole.guest),
    ]) {
      test('says $who has no vote, with the role', () {
        final view = _view(voterId: aUserId(userId));

        expect(view, isA<VoteViewIneligible>());
        view as VoteViewIneligible;
        expect(view.error, isA<NoVotingRightsError>());
        expect(view.role, role);
      });
    }

    test('says a user who is not in the meeting is not a participant', () {
      final view = _view(voterId: aUserId('user-9'));

      expect(view, isA<VoteViewIneligible>());
      view as VoteViewIneligible;
      expect(view.error, isA<NotAParticipantError>());
      expect(view.role, isNull);
    });

    test('says a closed resolution is closed', () {
      final closed = aResolution(status: ResolutionStatus.closed);

      final view = _view(meeting: _meetingWith(closed), resolution: closed);

      expect(view, isA<VoteViewIneligible>());
      expect((view as VoteViewIneligible).error, isA<ResolutionClosedError>());
    });

    test('says a voting window that is over is over, at the '
        'instant the meeting was loaded', () {
      final lapsed = aResolution(closesAt: at(millisPerHour));

      final over = _view(
        meeting: _meetingWith(lapsed),
        resolution: lapsed,
        at: at(millisPerHour),
      );
      final before = _view(
        meeting: _meetingWith(lapsed),
        resolution: lapsed,
        at: at(millisPerHour - 1),
      );

      expect(over, isA<VoteViewIneligible>());
      expect((over as VoteViewIneligible).error, isA<VotingWindowOverError>());
      expect(before, isA<VoteViewEligible>());
    });

    test('says a user who voted, as the server records '
        'it, has voted: a vote is final', () {
      final voted = aResolution(recordedVote: VoteChoice.against);

      final view = _view(meeting: _meetingWith(voted), resolution: voted);

      expect(view, isA<VoteViewIneligible>());
      expect(
        (view as VoteViewIneligible).error,
        const AlreadyVotedError(source: AlreadyVotedSource.recorded),
      );
    });

    test('says a vote waiting to be sent is waiting, with its '
        'choice, whatever the rule says now', () {
      final waiting = aPendingVote(aVote(choice: VoteChoice.abstain));
      final lapsed = aResolution(closesAt: at(millisPerHour));

      final open = _view(outbox: _outbox(pending: [waiting]));
      final over = _view(
        meeting: _meetingWith(lapsed),
        resolution: lapsed,
        at: at(millisPerHour),
        outbox: _outbox(pending: [waiting]),
      );

      expect(open, isA<VoteViewQueued>());
      expect((open as VoteViewQueued).choice, VoteChoice.abstain);
      expect(over, isA<VoteViewQueued>());
      expect((over as VoteViewQueued).choice, VoteChoice.abstain);
    });

    test('says a rejected vote was rejected, with its '
        'reason, before anything else', () {
      final rejected = aRejectedVote(aVote(), voteUndeliverable(5));
      final closed = aResolution(status: ResolutionStatus.closed);

      final open = _view(outbox: _outbox(rejected: [rejected]));
      final shut = _view(
        meeting: _meetingWith(closed),
        resolution: closed,
        outbox: _outbox(rejected: [rejected]),
      );

      expect(open, isA<VoteViewRejected>());
      expect((open as VoteViewRejected).reason, voteUndeliverable(5));
      expect(shut, isA<VoteViewRejected>());
      expect((shut as VoteViewRejected).reason, voteUndeliverable(5));
    });

    test(
      'ignores the votes of the outbox that belong to another resolution',
      () {
        final other = aPendingVote(
          aVote(resolutionId: aResolutionId('resolution-2')),
        );
        final otherRejected = aRejectedVote(
          aVote(resolutionId: aResolutionId('resolution-3')),
        );

        final view = _view(
          outbox: _outbox(pending: [other], rejected: [otherRejected]),
        );

        expect(view, isA<VoteViewEligible>());
      },
    );

    test('judges the right resolution among several, '
        'wherever it sits in the agenda', () {
      final second = aResolution(
        id: aResolutionId('resolution-2'),
        status: ResolutionStatus.closed,
      );
      final meeting = aMeeting(
        agenda: [
          anAgendaItem(resolution: _resolution),
          anAgendaItem(
            resolution: second,
            position: 2,
            id: anAgendaItemId('agenda-2'),
          ),
        ],
        participants: [aParticipant()],
      );

      final first = _view(meeting: meeting, resolution: _resolution);
      final last = _view(meeting: meeting, resolution: second);

      expect(first, isA<VoteViewEligible>());
      expect(last, isA<VoteViewIneligible>());
      expect((last as VoteViewIneligible).error, isA<ResolutionClosedError>());
    });
  });
}
