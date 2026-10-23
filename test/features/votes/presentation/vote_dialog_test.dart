import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/presentation/components/vote_dialog.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/presentation/test_app.dart';
import 'votes_presentation_support.dart';

// The confirmation step of a vote: what it states before anything is cast, and
// how every outcome that is not a success is told in the dialog.

const String _title = 'Approve the budget';

Future<ProviderContainer> _pumpDialog(
  WidgetTester tester, {
  VoteChoice choice = VoteChoice.forChoice,
  bool offline = false,
  bool pending = false,
  AppError? failure,
  VoidCallback? onConfirm,
  VoidCallback? onDismiss,
  Locale locale = const Locale('en'),
}) => pumpScreen(
  tester,
  SingleChildScrollView(
    child: VoteDialog(
      choice: choice,
      resolutionTitle: _title,
      offline: offline,
      pending: pending,
      failure: failure,
      onConfirm: onConfirm ?? () {},
      onDismiss: onDismiss ?? () {},
    ),
  ),
  locale: locale,
);

void main() {
  final en = l10nOf();

  group('VoteDialog', () {
    testWidgets(
      'states what the user is about to do, that it is final, and that a '
      'biometric confirmation follows',
      (tester) async {
        final providers = await _pumpDialog(tester);

        expect(byTestId(VotesTestIds.voteDialog), findsOneWidget);
        expect(find.text(en.votesVotingConfirmTitle), findsOneWidget);
        expect(find.text(_title), findsOneWidget);
        expect(
          find.descendant(
            of: byTestId(VotesTestIds.voteDialogChoice),
            matchRoot: true,
            matching: find.text(
              en.votesVotingConfirmChoice(en.votesVoteChoiceFor),
            ),
          ),
          findsOneWidget,
        );
        expect(find.text(en.votesVotingConfirmFinal), findsOneWidget);
        expect(byTestId(VotesTestIds.voteDialogFinal), findsOneWidget);
        expect(find.text(en.votesVotingConfirmBiometric), findsOneWidget);
        expect(byTestId(VotesTestIds.voteDialogOffline), findsNothing);
        expect(byTestId(VotesTestIds.voteDialogError), findsNothing);
        expect(byTestId(VotesTestIds.voteConfirm), findsOneWidget);
        expect(byTestId(VotesTestIds.voteCancel), findsOneWidget);
        expect(byTestId(VotesTestIds.voteClose), findsNothing);
        await endApp(tester, providers);
      },
    );

    for (final (choice, label) in [
      (VoteChoice.forChoice, en.votesVoteChoiceFor),
      (VoteChoice.against, en.votesVoteChoiceAgainst),
      (VoteChoice.abstain, en.votesVoteChoiceAbstain),
    ]) {
      testWidgets('names the choice under review: ${choice.value}', (
        tester,
      ) async {
        final providers = await _pumpDialog(tester, choice: choice);

        expect(find.text(en.votesVotingConfirmChoice(label)), findsOneWidget);
        await endApp(tester, providers);
      });
    }

    testWidgets('says the vote will be saved and sent later when offline', (
      tester,
    ) async {
      final providers = await _pumpDialog(tester, offline: true);

      expect(
        find.descendant(
          of: byTestId(VotesTestIds.voteDialogOffline),
          matchRoot: true,
          matching: find.text(en.votesVotingConfirmOffline),
        ),
        findsOneWidget,
      );
      await endApp(tester, providers);
    });

    testWidgets('is written in French when the device is', (tester) async {
      final fr = l10nOf(const Locale('fr'));
      final providers = await _pumpDialog(tester, locale: const Locale('fr'));

      expect(find.text(fr.votesVotingConfirmTitle), findsOneWidget);
      expect(find.text(fr.votesVotingConfirm), findsOneWidget);
      expect(find.text(fr.coreCommonCancel), findsOneWidget);
      await endApp(tester, providers);
    });

    testWidgets('calls onConfirm and onDismiss from its buttons', (
      tester,
    ) async {
      var confirmed = 0;
      var dismissed = 0;
      final providers = await _pumpDialog(
        tester,
        onConfirm: () => confirmed += 1,
        onDismiss: () => dismissed += 1,
      );

      await tester.tap(byTestId(VotesTestIds.voteConfirm));
      await tester.tap(byTestId(VotesTestIds.voteCancel));

      expect(confirmed, 1);
      expect(dismissed, 1);
      await endApp(tester, providers);
    });

    testWidgets(
      'is busy while the vote is being cast: confirm cannot be pressed again '
      'and cancel is disabled',
      (tester) async {
        var confirmed = 0;
        var dismissed = 0;
        final providers = await _pumpDialog(
          tester,
          pending: true,
          onConfirm: () => confirmed += 1,
          onDismiss: () => dismissed += 1,
        );

        expect(find.text(en.votesVotingConfirming), findsOneWidget);
        expect(find.text(en.votesVotingConfirm), findsNothing);
        await tester.tap(byTestId(VotesTestIds.voteConfirm));
        await tester.tap(byTestId(VotesTestIds.voteCancel));

        expect(confirmed, 0);
        expect(dismissed, 0);
        await endApp(tester, providers);
      },
    );

    group('when the last attempt failed', () {
      testWidgets('tells why, in the dialog, with the text of the failure', (
        tester,
      ) async {
        final providers = await _pumpDialog(
          tester,
          failure: biometricCancelled(),
        );

        expect(
          find.descendant(
            of: byTestId(VotesTestIds.voteDialogError),
            matchRoot: true,
            matching: find.text(en.votesVoteBiometricBiometricCancelled),
          ),
          findsOneWidget,
        );
        await endApp(tester, providers);
      });

      testWidgets('tells a vote already cast by where it is', (tester) async {
        final providers = await _pumpDialog(
          tester,
          failure: const AlreadyVotedError(source: AlreadyVotedSource.queued),
        );

        expect(
          find.text(en.votesVotingReasonAlreadyVotedQueued),
          findsOneWidget,
        );
        await endApp(tester, providers);
      });

      for (final (name, failure) in <(String, AppError)>[
        ('biometricCancelled', biometricCancelled()),
        ('biometricFailed', biometricFailed()),
        ('biometricLockedOut', biometricLockedOut()),
        ('storageWriteFailed', storageWriteFailed()),
        ('networkUnavailable', networkUnavailable()),
        ('unexpected', const UnexpectedError()),
        ('storageReadFailed', storageReadFailed()),
      ]) {
        testWidgets('keeps Confirm and Cancel when $name can be tried again', (
          tester,
        ) async {
          final providers = await _pumpDialog(tester, failure: failure);

          expect(byTestId(VotesTestIds.voteConfirm), findsOneWidget);
          expect(byTestId(VotesTestIds.voteCancel), findsOneWidget);
          expect(byTestId(VotesTestIds.voteClose), findsNothing);
          await endApp(tester, providers);
        });
      }

      for (final (name, failure) in <(String, AppError)>[
        ('resolutionClosed', const ResolutionClosedError()),
        ('votingWindowOver', const VotingWindowOverError()),
        (
          'alreadyVoted',
          const AlreadyVotedError(source: AlreadyVotedSource.recorded),
        ),
        ('noVotingRights', const NoVotingRightsError()),
        ('biometricUnavailable', biometricUnavailable()),
        ('biometricNotEnrolled', biometricNotEnrolled()),
        ('sessionExpired', sessionExpired()),
        (
          'votePreviouslyRejected',
          votePreviouslyRejected(const ResolutionClosedError()),
        ),
        ('voteInProgress', voteInProgress()),
      ]) {
        testWidgets('replaces both with a single Close when $name is final', (
          tester,
        ) async {
          var dismissed = 0;
          final providers = await _pumpDialog(
            tester,
            failure: failure,
            onDismiss: () => dismissed += 1,
          );

          expect(byTestId(VotesTestIds.voteClose), findsOneWidget);
          expect(byTestId(VotesTestIds.voteConfirm), findsNothing);
          expect(byTestId(VotesTestIds.voteCancel), findsNothing);

          await tester.tap(byTestId(VotesTestIds.voteClose));
          expect(dismissed, 1);
          await endApp(tester, providers);
        });
      }
    });
  });
}
