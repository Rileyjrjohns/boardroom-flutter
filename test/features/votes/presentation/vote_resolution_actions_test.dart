import 'dart:async';

import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/meetings/presentation/slots/resolution_actions.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/presentation/slots/vote_resolution_actions.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/create_fakes.dart';
import '../../../support/presentation/test_app.dart';
import 'votes_presentation_support.dart';

// What the votes plug into the resolutions of the meetings (the slot declared
// by the meetings): one reading of the votes of the user for the whole meeting,
// the line about their vote and what they can do about it under each
// resolution, the confirmation that casts a vote, and a failure to read the
// votes told once, at the top.

final Meeting _meeting = aMeeting();
final Resolution _resolution = aResolution();
final String _id = _resolution.id;

Future<ProviderContainer> _pumpActions(
  WidgetTester tester, {
  Fakes? fakes,
  Meeting? meeting,
  Resolution? resolution,
  Locale locale = const Locale('en'),
}) {
  final theMeeting = meeting ?? _meeting;
  final theFakes = fakes ?? createFakes();
  theFakes.meetings.addMeeting(theMeeting);
  return pumpScreen(
    tester,
    SingleChildScrollView(
      child: Column(
        children: [
          for (final item in theMeeting.agenda)
            if (item.resolution case final each?)
              VoteResolutionActions(
                meeting: theMeeting,
                resolution: resolution != null && each.id == resolution.id
                    ? resolution
                    : each,
              ),
        ],
      ),
    ),
    app: TestApp(fakes: theFakes),
    locale: locale,
  );
}

// The dialog is as tall as its text: its buttons may be below the fold.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
}

Finder _text(String text) => find.text(text);

Future<void> _choose(WidgetTester tester, VoteChoice choice) async {
  await tester.ensureVisible(byTestId(voteChoiceTestId(_id, choice.value)));
  await tester.tap(byTestId(voteChoiceTestId(_id, choice.value)));
  await tester.pumpAndSettle();
}

void main() {
  final en = l10nOf();

  group('voteResolutionActions', () {
    testWidgets('is plugged into the slot of the meetings by the composition', (
      tester,
    ) async {
      final providers = await _pumpActions(tester);

      expect(providers.read(resolutionActionsProvider), isNotNull);
      await endApp(tester, providers);
    });

    testWidgets(
      'offers the choices under a resolution the user may vote on, once '
      'their votes are read',
      (tester) async {
        final providers = await _pumpActions(tester);
        await tester.pumpAndSettle();

        expect(byTestId(voteChoicesTestId(_id)), findsOneWidget);
        expect(byTestId(VotesTestIds.votingError), findsNothing);
        expect(_text(en.votesVotingChoose), findsOneWidget);
        for (final choice in VoteChoice.values) {
          expect(byTestId(voteChoiceTestId(_id, choice.value)), findsOneWidget);
        }
        await endApp(tester, providers);
      },
    );

    testWidgets(
      'says nothing of the vote of the user, and offers nothing, while '
      'their votes are not read',
      (tester) async {
        final providers = await _pumpActions(tester);

        expect(_text(en.meetingsMeetingResolutionNoVote), findsNothing);
        expect(byTestId(voteChoicesTestId(_id)), findsNothing);
        expect(byTestId(VotesTestIds.votingLoading), findsOneWidget);
        await tester.pumpAndSettle();
        await endApp(tester, providers);
      },
    );

    testWidgets('tells "you have not voted" once the votes are known', (
      tester,
    ) async {
      final providers = await _pumpActions(tester);
      await tester.pumpAndSettle();

      expect(_text(en.meetingsMeetingResolutionNoVote), findsOneWidget);
      expect(byTestId(VotesTestIds.votingLoading), findsNothing);
      await endApp(tester, providers);
    });

    testWidgets(
      'tells at the top that the votes could not be read, with a way to try '
      'again, and offers nothing meanwhile',
      (tester) async {
        final fakes = createFakes()..auth.readFailure = storageReadFailed();
        final providers = await _pumpActions(tester, fakes: fakes);
        await tester.pumpAndSettle();

        expect(byTestId(VotesTestIds.votingError), findsOneWidget);
        expect(byTestId(voteChoicesTestId(_id)), findsNothing);
        expect(_text(en.coreErrorsStorageReadFailed), findsOneWidget);
        expect(_text(en.meetingsMeetingResolutionNoVote), findsNothing);

        fakes.auth.readFailure = null;
        await tester.tap(byTestId(CoreTestIds.retryButton));
        await tester.pumpAndSettle();

        expect(byTestId(VotesTestIds.votingError), findsNothing);
        expect(byTestId(voteChoicesTestId(_id)), findsOneWidget);
        await endApp(tester, providers);
      },
    );

    testWidgets(
      'tells that the votes could not be read once for the meeting, above '
      'its first resolution',
      (tester) async {
        final fakes = createFakes()..auth.readFailure = storageReadFailed();
        final providers = await _pumpActions(
          tester,
          fakes: fakes,
          meeting: aMeetingWithAgenda(),
        );
        await tester.pumpAndSettle();

        expect(byTestId(VotesTestIds.votingError), findsOneWidget);
        await endApp(tester, providers);
      },
    );

    group('the vote of the user, by view', () {
      testWidgets('says a vote that waits is waiting, and offers no choice', (
        tester,
      ) async {
        final fakes = createFakes()
          ..outbox.seed([aPendingVote(aVote(choice: VoteChoice.abstain))]);
        final providers = await _pumpActions(tester, fakes: fakes);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: byTestId(voteOutcomeTestId(_id)),
            matchRoot: true,
            matching: _text(en.votesVotingQueued),
          ),
          findsOneWidget,
        );
        expect(
          _text(
            en.meetingsMeetingResolutionYourVoteQueued(
              en.votesVoteChoiceAbstain,
            ),
          ),
          findsOneWidget,
        );
        expect(byTestId(voteChoicesTestId(_id)), findsNothing);
        await endApp(tester, providers);
      });

      testWidgets(
        'tells why a vote was rejected, and offers to acknowledge it, after '
        'which the user can vote again',
        (tester) async {
          final fakes = createFakes()
            ..outbox.seed([aRejectedVote(aVote(), voteUndeliverable(5))]);
          final providers = await _pumpActions(tester, fakes: fakes);
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: byTestId(voteNoticeTestId(_id)),
              matchRoot: true,
              matching: _text(
                en.votesVotingRejected(
                  en.votesVotingReasonVoteUndeliverable(5),
                ),
              ),
            ),
            findsOneWidget,
          );
          expect(byTestId(voteChoicesTestId(_id)), findsNothing);

          await tester.ensureVisible(byTestId(acknowledgeTestId(_id)));
          await tester.tap(byTestId(acknowledgeTestId(_id)));
          await tester.pumpAndSettle();

          expect(byTestId(voteNoticeTestId(_id)), findsNothing);
          expect(byTestId(voteChoicesTestId(_id)), findsOneWidget);
          expect(fakes.outbox.snapshot(), isEmpty);
          await endApp(tester, providers);
        },
      );

      testWidgets(
        'tells the role of a user whose role carries no vote, as a text with '
        'no control',
        (tester) async {
          final fakes = createFakes()
            ..auth.session = aSession(user: aUser(id: aUserId('user-3')));
          final providers = await _pumpActions(tester, fakes: fakes);
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: byTestId(voteNoticeTestId(_id)),
              matchRoot: true,
              matching: _text(
                en.votesVotingNoVotingRightsAs(
                  en.meetingsParticipantRoleSecretary,
                ),
              ),
            ),
            findsOneWidget,
          );
          expect(byTestId(voteChoicesTestId(_id)), findsNothing);
          expect(
            ParticipantRole.secretary,
            _meeting.participants
                .firstWhere(
                  (participant) => participant.userId == aUserId('user-3'),
                )
                .role,
          );
          await endApp(tester, providers);
        },
      );

      testWidgets('tells a vote already recorded, with the vote of the user', (
        tester,
      ) async {
        final voted = aResolution(recordedVote: VoteChoice.against);
        final providers = await _pumpActions(
          tester,
          meeting: aMeeting(agenda: [anAgendaItem(resolution: voted)]),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: byTestId(voteNoticeTestId(_id)),
            matchRoot: true,
            matching: _text(en.votesVotingReasonAlreadyVotedRecorded),
          ),
          findsOneWidget,
        );
        expect(
          _text(
            en.meetingsMeetingResolutionYourVote(en.votesVoteChoiceAgainst),
          ),
          findsOneWidget,
        );
        await endApp(tester, providers);
      });

      testWidgets('tells a closed resolution is closed', (tester) async {
        final closed = aResolution(status: ResolutionStatus.closed);
        final providers = await _pumpActions(
          tester,
          meeting: aMeeting(agenda: [anAgendaItem(resolution: closed)]),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: byTestId(voteNoticeTestId(_id)),
            matchRoot: true,
            matching: _text(en.votesVotingReasonResolutionClosed),
          ),
          findsOneWidget,
        );
        await endApp(tester, providers);
      });
    });

    group('casting a vote', () {
      testWidgets(
        'opens the confirmation with the choice, and casts nothing until it '
        'is confirmed',
        (tester) async {
          final fakes = createFakes();
          final providers = await _pumpActions(tester, fakes: fakes);
          await tester.pumpAndSettle();

          await _choose(tester, VoteChoice.against);

          expect(byTestId(VotesTestIds.voteDialog), findsOneWidget);
          expect(
            _text(en.votesVotingConfirmChoice(en.votesVoteChoiceAgainst)),
            findsOneWidget,
          );
          expect(_text(_resolution.title), findsWidgets);
          expect(byTestId(VotesTestIds.voteDialogOffline), findsNothing);
          expect(fakes.votes.received, isEmpty);
          expect(fakes.biometricGate.prompts, isEmpty);
          await endApp(tester, providers);
        },
      );

      testWidgets('closes the confirmation, casting nothing, on Cancel', (
        tester,
      ) async {
        final fakes = createFakes();
        final providers = await _pumpActions(tester, fakes: fakes);
        await tester.pumpAndSettle();
        await _choose(tester, VoteChoice.forChoice);

        await _tap(tester, byTestId(VotesTestIds.voteCancel));
        await tester.pumpAndSettle();

        expect(byTestId(VotesTestIds.voteDialog), findsNothing);
        expect(fakes.votes.received, isEmpty);
        expect(byTestId(voteChoicesTestId(_id)), findsOneWidget);
        await endApp(tester, providers);
      });

      testWidgets('asks for the biometric proof, casts the vote, closes the '
          'confirmation and tells the vote was recorded', (tester) async {
        final fakes = createFakes();
        final providers = await _pumpActions(tester, fakes: fakes);
        await tester.pumpAndSettle();
        await _choose(tester, VoteChoice.forChoice);

        await _tap(tester, byTestId(VotesTestIds.voteConfirm));
        await tester.pumpAndSettle();

        expect(fakes.biometricGate.prompts, hasLength(1));
        expect(fakes.votes.received.single.choice, VoteChoice.forChoice);
        expect(byTestId(VotesTestIds.voteDialog), findsNothing);
        expect(
          find.descendant(
            of: byTestId(voteOutcomeTestId(_id)),
            matchRoot: true,
            matching: _text(en.votesVotingSubmitted),
          ),
          findsOneWidget,
        );
        await endApp(tester, providers);
      });

      testWidgets('saves the vote on the device when offline, says so in the '
          'confirmation, and then tells it waits to be sent', (tester) async {
        // The server cannot be reached when the vote is sent; the meeting
        // itself was read before.
        final fakes = createFakes()
          ..votes.answerNext(err(networkUnavailable()));
        final providers = await _pumpActions(tester, fakes: fakes);
        providers
            .read(connectivityStateProvider.notifier)
            .set(ConnectivityStatus.offline);
        await tester.pumpAndSettle();
        await _choose(tester, VoteChoice.abstain);
        expect(
          find.descendant(
            of: byTestId(VotesTestIds.voteDialogOffline),
            matchRoot: true,

            matching: _text(en.votesVotingConfirmOffline),
          ),
          findsOneWidget,
        );

        await _tap(tester, byTestId(VotesTestIds.voteConfirm));
        await tester.pumpAndSettle();

        expect(byTestId(VotesTestIds.voteDialog), findsNothing);
        expect(fakes.outbox.snapshot(), hasLength(1));
        expect(
          find.descendant(
            of: byTestId(voteOutcomeTestId(_id)),
            matchRoot: true,
            matching: _text(en.votesVotingQueued),
          ),
          findsOneWidget,
        );
        expect(byTestId(voteChoicesTestId(_id)), findsNothing);
        expect(
          _text(
            en.meetingsMeetingResolutionYourVoteQueued(
              en.votesVoteChoiceAbstain,
            ),
          ),
          findsOneWidget,
        );
        await endApp(tester, providers);
      });

      testWidgets(
        'keeps the confirmation open, with the reason and the choice still '
        'under review, when the user cancels the biometric prompt, and lets '
        'them try again',
        (tester) async {
          final fakes = createFakes()
            ..biometricGate.authentication = err(biometricCancelled());
          final providers = await _pumpActions(tester, fakes: fakes);
          await tester.pumpAndSettle();
          await _choose(tester, VoteChoice.forChoice);

          await _tap(tester, byTestId(VotesTestIds.voteConfirm));
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: byTestId(VotesTestIds.voteDialogError),
              matchRoot: true,

              matching: _text(en.votesVoteBiometricBiometricCancelled),
            ),
            findsOneWidget,
          );
          expect(byTestId(VotesTestIds.voteConfirm), findsOneWidget);
          expect(fakes.votes.received, isEmpty);

          fakes.biometricGate.authentication = ok<void>(null);
          await _tap(tester, byTestId(VotesTestIds.voteConfirm));
          await tester.pumpAndSettle();

          expect(byTestId(VotesTestIds.voteDialog), findsNothing);
          expect(fakes.votes.received, hasLength(1));
          await endApp(tester, providers);
        },
      );

      testWidgets(
        'offers only Close when the server says the resolution is closed, and '
        'forgets the choice when it is closed',
        (tester) async {
          final fakes = createFakes();
          final closed = aResolution(status: ResolutionStatus.closed);
          fakes.meetings.addMeeting(
            aMeeting(agenda: [anAgendaItem(resolution: closed)]),
          );
          final providers = await _pumpActions(tester, fakes: fakes);
          // The meeting the server holds is the closed one; the screen was
          // drawn from an older copy, where the resolution was still open.
          fakes.meetings.addMeeting(
            aMeeting(agenda: [anAgendaItem(resolution: closed)]),
          );
          await tester.pumpAndSettle();
          await _choose(tester, VoteChoice.forChoice);

          await _tap(tester, byTestId(VotesTestIds.voteConfirm));
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: byTestId(VotesTestIds.voteDialogError),
              matchRoot: true,

              matching: _text(en.votesVotingReasonResolutionClosed),
            ),
            findsOneWidget,
          );
          expect(byTestId(VotesTestIds.voteClose), findsOneWidget);
          expect(byTestId(VotesTestIds.voteConfirm), findsNothing);
          expect(fakes.votes.received, isEmpty);

          await _tap(tester, byTestId(VotesTestIds.voteClose));
          await tester.pumpAndSettle();

          expect(byTestId(VotesTestIds.voteDialog), findsNothing);
          await endApp(tester, providers);
        },
      );

      testWidgets(
        'casts one vote however many times Confirm is pressed, and cannot '
        'be cancelled while the vote is being cast',
        (tester) async {
          final gate = Completer<void>();
          final fakes = createFakes();
          fakes.biometricGate.onPrompt = () => gate.future;
          final providers = await _pumpActions(tester, fakes: fakes);
          await tester.pumpAndSettle();
          await _choose(tester, VoteChoice.forChoice);

          await _tap(tester, byTestId(VotesTestIds.voteConfirm));
          await tester.pump();
          await _tap(tester, byTestId(VotesTestIds.voteConfirm));
          await _tap(tester, byTestId(VotesTestIds.voteCancel));
          await tester.pump();

          expect(_text(en.votesVotingConfirming), findsOneWidget);
          expect(byTestId(VotesTestIds.voteDialog), findsOneWidget);
          expect(fakes.biometricGate.prompts, hasLength(1));

          gate.complete();
          await tester.pumpAndSettle();

          expect(fakes.votes.received, hasLength(1));
          expect(byTestId(VotesTestIds.voteDialog), findsNothing);
          await endApp(tester, providers);
        },
      );
    });

    testWidgets('is written in French when the device is', (tester) async {
      final fr = l10nOf(const Locale('fr'));
      final providers = await _pumpActions(tester, locale: const Locale('fr'));
      await tester.pumpAndSettle();

      expect(_text(fr.votesVotingChoose), findsOneWidget);
      expect(_text(fr.votesVoteChoiceAbstain), findsOneWidget);
      expect(_text(fr.meetingsMeetingResolutionNoVote), findsOneWidget);
      await endApp(tester, providers);
    });
  });
}
