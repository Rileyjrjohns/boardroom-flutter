import 'dart:async';

import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/presentation/demo/demo_controls.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/presentation/screens/pending_votes_screen.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/create_fakes.dart';
import '../../../support/presentation/fake_demo_network.dart';
import '../../../support/presentation/test_app.dart';
import 'votes_presentation_support.dart';

final ResolutionId _r1 = aResolutionId('r1');
final ResolutionId _r2 = aResolutionId('r2');
final ResolutionId _r3 = aResolutionId('r3');
final MeetingId _meetingA = aMeetingId('meeting-a');
final MeetingId _meetingB = aMeetingId('meeting-b');

final PendingVote _first = aPendingVote(
  aVote(resolutionId: _r1, meetingId: _meetingA, castAt: at(-5000)),
);
final PendingVote _second = aPendingVote(
  aVote(
    resolutionId: _r2,
    meetingId: _meetingB,
    choice: VoteChoice.abstain,
    castAt: at(-4000),
  ),
);
final RejectedVote _rejected = aRejectedVote(
  aVote(
    resolutionId: _r3,
    meetingId: _meetingA,
    choice: VoteChoice.against,
    castAt: at(-3000),
  ),
);

Future<ProviderContainer> _pumpPending(
  WidgetTester tester, {
  Fakes? fakes,
  TestApp? app,
  Locale locale = const Locale('en'),
}) => pumpRouted(
  tester,
  const PendingVotesScreen(),
  app: app ?? TestApp(fakes: fakes),
  locale: locale,
);

/// The rows of the section [sectionId] whose test id starts with [prefix].
Iterable<String> _rowIds(WidgetTester tester, String sectionId, String prefix) {
  final rows = find.descendant(
    of: byTestId(sectionId),
    matchRoot: true,
    matching: find.byWidgetPredicate((widget) {
      final key = widget.key;
      return widget is Container &&
          key is ValueKey<String> &&
          key.value.startsWith(prefix);
    }),
  );
  return tester
      .widgetList(rows)
      .map((row) => (row.key! as ValueKey<String>).value);
}

Finder _within(String id, Finder matching) =>
    find.descendant(of: byTestId(id), matchRoot: true, matching: matching);

void main() {
  final en = l10nOf();
  final fr = l10nOf(const Locale('fr'));
  late final Formatters formatters;

  setUpAll(() async {
    await initializeDateFormatting('en');
    formatters = Formatters('en');
  });

  group('PendingVotesScreen', () {
    testWidgets('shows a loading state, then the votes', (tester) async {
      final fakes = createFakes()..outbox.seed([_first]);
      final providers = await _pumpPending(tester, fakes: fakes);
      expect(byTestId(VotesTestIds.pendingVotesLoading), findsOneWidget);

      await tester.pumpAndSettle();

      expect(byTestId(VotesTestIds.pendingVotesScreen), findsOneWidget);
      expect(byTestId(VotesTestIds.pendingVotesLoading), findsNothing);
      await endApp(tester, providers);
    });

    testWidgets('says no vote is waiting when the outbox is empty', (
      tester,
    ) async {
      final providers = await _pumpPending(tester);
      await tester.pumpAndSettle();

      expect(
        _within(
          VotesTestIds.pendingVotesEmpty,
          find.text(en.votesPendingVotesEmpty),
        ),
        findsOneWidget,
      );
      expect(find.text(en.votesPendingVotesExplanation), findsOneWidget);
      expect(byTestId(VotesTestIds.pendingVotesWaiting), findsNothing);
      expect(byTestId(VotesTestIds.pendingVotesRejected), findsNothing);
      await endApp(tester, providers);
    });

    group('the votes that wait', () {
      testWidgets(
        'are listed oldest first, each with its choice and the date it was '
        'cast',
        (tester) async {
          final fakes = createFakes()..outbox.seed([_first, _second]);
          final providers = await _pumpPending(tester, fakes: fakes);
          await tester.pumpAndSettle();

          expect(
            _rowIds(tester, VotesTestIds.pendingVotesWaiting, 'pending-vote-'),
            [pendingVoteTestId(_r1), pendingVoteTestId(_r2)],
          );
          expect(
            _within(
              VotesTestIds.pendingVotesWaiting,
              find.text(en.votesPendingVotesWaiting),
            ),
            findsOneWidget,
          );
          final first = byTestId(pendingVoteTestId(_r1));
          expect(
            find.descendant(
              of: first,
              matching: find.text(
                en.meetingsMeetingResolutionYourVote(en.votesVoteChoiceFor),
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: first,
              matching: find.text(
                en.votesPendingVotesCastAt(formatters.dateTime(at(-5000))),
              ),
            ),
            findsOneWidget,
          );
          expect(byTestId(VotesTestIds.pendingVotesRejected), findsNothing);
          await endApp(tester, providers);
        },
      );

      testWidgets('lead to the meeting they were cast in', (tester) async {
        final fakes = createFakes()..outbox.seed([_first, _second]);
        final providers = await _pumpPending(tester, fakes: fakes);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: byTestId(pendingVoteTestId(_r1)),
            matching: find.text(en.votesPendingVotesOpenMeeting),
          ),
          findsOneWidget,
        );

        await tester.ensureVisible(byTestId(openVoteMeetingTestId(_r2)));
        await tester.tap(byTestId(openVoteMeetingTestId(_r2)));
        await tester.pumpAndSettle();

        expect(find.byKey(openedMeetingKey(_meetingB)), findsOneWidget);
        await endApp(tester, providers);
      });

      testWidgets('are not shown to another user of the device', (
        tester,
      ) async {
        final fakes = createFakes()
          ..outbox.seed([
            _first,
            aPendingVote(aVote(resolutionId: _r2, voterId: aUserId('user-2'))),
          ]);
        final providers = await _pumpPending(tester, fakes: fakes);
        await tester.pumpAndSettle();

        expect(byTestId(pendingVoteTestId(_r2)), findsNothing);
        expect(byTestId(pendingVoteTestId(_r1)), findsOneWidget);
        await endApp(tester, providers);
      });
    });

    group('the votes that were rejected', () {
      testWidgets(
        'are listed apart, with the reason and the date, and offer to '
        'acknowledge them',
        (tester) async {
          final fakes = createFakes()..outbox.seed([_first, _rejected]);
          final providers = await _pumpPending(tester, fakes: fakes);
          await tester.pumpAndSettle();

          final row = byTestId(rejectedVoteTestId(_r3));
          expect(
            _within(
              VotesTestIds.pendingVotesRejected,
              find.text(en.votesPendingVotesRejected),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: row,
              matching: find.text(en.votesVotingReasonResolutionClosed),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: row,
              matching: find.text(
                en.meetingsMeetingResolutionYourVote(en.votesVoteChoiceAgainst),
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: row,
              matching: find.text(
                en.votesPendingVotesRejectedAt(formatters.dateTime(at(60000))),
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: row,
              matching: find.text(en.votesVotingAcknowledge),
            ),
            findsOneWidget,
          );
          expect(byTestId(rejectedVoteTestId(_r1)), findsNothing);
          await endApp(tester, providers);
        },
      );

      testWidgets(
        'tell a vote that was given up in words that count the attempts',
        (tester) async {
          final fakes = createFakes()
            ..outbox.seed([
              aRejectedVote(aVote(resolutionId: _r3), voteUndeliverable(5)),
            ]);
          final providers = await _pumpPending(tester, fakes: fakes);
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: byTestId(rejectedVoteTestId(_r3)),
              matching: find.text(en.votesVotingReasonVoteUndeliverable(5)),
            ),
            findsOneWidget,
          );
          await endApp(tester, providers);
        },
      );

      testWidgets(
        'are removed from the list when acknowledged, and the vote leaves '
        'the outbox',
        (tester) async {
          final fakes = createFakes()..outbox.seed([_first, _rejected]);
          final providers = await _pumpPending(tester, fakes: fakes);
          await tester.pumpAndSettle();

          await tester.ensureVisible(byTestId(acknowledgeTestId(_r3)));
          await tester.tap(byTestId(acknowledgeTestId(_r3)));
          await tester.pumpAndSettle();

          expect(byTestId(rejectedVoteTestId(_r3)), findsNothing);
          expect(byTestId(VotesTestIds.pendingVotesRejected), findsNothing);
          expect(
            fakes.outbox.snapshot().map((entry) => entry.vote.resolutionId),
            [_r1],
          );
          expect(byTestId(pendingVoteTestId(_r1)), findsOneWidget);
          await endApp(tester, providers);
        },
      );

      testWidgets(
        'stay, with the reason the acknowledgement failed, when the outbox '
        'cannot be written',
        (tester) async {
          final fakes = createFakes()
            ..outbox.seed([_rejected])
            ..outbox.removeFailure = storageWriteFailed();
          final providers = await _pumpPending(tester, fakes: fakes);
          await tester.pumpAndSettle();

          await tester.ensureVisible(byTestId(acknowledgeTestId(_r3)));
          await tester.tap(byTestId(acknowledgeTestId(_r3)));
          await tester.pumpAndSettle();

          expect(
            find.text(en.votesVotingFailureStorageWriteFailed),
            findsOneWidget,
          );
          expect(byTestId(rejectedVoteTestId(_r3)), findsOneWidget);
          await endApp(tester, providers);
        },
      );

      testWidgets(
        'are acknowledged once, however many times the button is pressed',
        (tester) async {
          final fakes = createFakes()..outbox.seed([_rejected]);
          late final CountingOutbox outbox;
          final providers = await _pumpPending(
            tester,
            app: TestApp(
              fakes: fakes,
              adaptPorts: (ports) {
                outbox = CountingOutbox(ports.outbox);
                return withOutbox(ports, outbox);
              },
            ),
          );
          await tester.pumpAndSettle();

          await tester.ensureVisible(byTestId(acknowledgeTestId(_r3)));
          await tester.tap(byTestId(acknowledgeTestId(_r3)));
          await tester.tap(byTestId(acknowledgeTestId(_r3)));
          await tester.pumpAndSettle();

          expect(outbox.removeCalls, 1);
          await endApp(tester, providers);
        },
      );
    });

    group('the saved votes that can no longer be read', () {
      final user = aUserId();

      testWidgets('says nothing when there are none', (tester) async {
        final fakes = createFakes()..outbox.seed([_first]);
        final providers = await _pumpPending(tester, fakes: fakes);
        await tester.pumpAndSettle();

        expect(byTestId(VotesTestIds.unreadableVotes), findsNothing);
        await endApp(tester, providers);
      });

      for (final (count, locale) in [
        (1, const Locale('en')),
        (3, const Locale('en')),
        (1, const Locale('fr')),
        (2, const Locale('fr')),
      ]) {
        testWidgets(
          'says how many there are, and that they are not sent: $count in '
          '${locale.languageCode}',
          (tester) async {
            final fakes = createFakes();
            for (var index = 0; index < count; index += 1) {
              fakes.outbox.seedUnreadable(user, 'k$index');
            }
            final providers = await _pumpPending(
              tester,
              fakes: fakes,
              locale: locale,
            );
            await tester.pumpAndSettle();

            expect(
              _within(
                VotesTestIds.unreadableVotes,
                find.text(l10nOf(locale).votesPendingVotesUnreadable(count)),
              ),
              findsOneWidget,
            );
            await endApp(tester, providers);
          },
        );
      }

      testWidgets(
        'is shown next to the votes that can be read, which are listed as '
        'usual',
        (tester) async {
          final fakes = createFakes()
            ..outbox.seed([_first])
            ..outbox.seedUnreadable(user, 'k1');
          final providers = await _pumpPending(tester, fakes: fakes);
          await tester.pumpAndSettle();

          expect(byTestId(pendingVoteTestId(_r1)), findsOneWidget);
          expect(byTestId(VotesTestIds.unreadableVotes), findsOneWidget);
          await endApp(tester, providers);
        },
      );

      testWidgets(
        'does not delete them by itself: the screen can be left and opened '
        'again, they are still there',
        (tester) async {
          final fakes = createFakes()..outbox.seedUnreadable(user, 'k1');
          final first = await _pumpPending(tester, fakes: fakes);
          await tester.pumpAndSettle();
          expect(byTestId(VotesTestIds.unreadableVotes), findsOneWidget);
          await endApp(tester, first);

          final second = await _pumpPending(tester, fakes: fakes);
          await tester.pumpAndSettle();

          expect(byTestId(VotesTestIds.unreadableVotes), findsOneWidget);
          expect(fakes.outbox.unreadableSnapshot(), hasLength(1));
          await endApp(tester, second);
        },
      );

      testWidgets(
        'asks for a confirmation that repeats how many, before anything is '
        'deleted',
        (tester) async {
          final fakes = createFakes()
            ..outbox.seedUnreadable(user, 'k1')
            ..outbox.seedUnreadable(user, 'k2');
          final providers = await _pumpPending(tester, fakes: fakes);
          await tester.pumpAndSettle();

          await tester.tap(byTestId(VotesTestIds.unreadableVotesDiscard));
          await tester.pumpAndSettle();

          expect(byTestId(VotesTestIds.unreadableVotesDialog), findsOneWidget);
          expect(find.text(en.votesPendingVotesDiscardTitle), findsOneWidget);
          expect(
            find.text(en.votesPendingVotesDiscardMessage(2)),
            findsOneWidget,
          );
          expect(fakes.outbox.unreadableSnapshot(), hasLength(2));
          await endApp(tester, providers);
        },
      );

      testWidgets('deletes nothing when the user cancels', (tester) async {
        final fakes = createFakes()..outbox.seedUnreadable(user, 'k1');
        final providers = await _pumpPending(tester, fakes: fakes);
        await tester.pumpAndSettle();
        await tester.tap(byTestId(VotesTestIds.unreadableVotesDiscard));
        await tester.pumpAndSettle();

        await tester.tap(byTestId(VotesTestIds.unreadableVotesCancel));
        await tester.pumpAndSettle();

        expect(fakes.outbox.unreadableSnapshot(), hasLength(1));
        expect(byTestId(VotesTestIds.unreadableVotesDialog), findsNothing);
        expect(byTestId(VotesTestIds.unreadableVotes), findsOneWidget);
        await endApp(tester, providers);
      });

      testWidgets('deletes them once the user confirms, and the notice goes', (
        tester,
      ) async {
        final fakes = createFakes()
          ..outbox.seed([_first])
          ..outbox.seedUnreadable(user, 'k1');
        final providers = await _pumpPending(tester, fakes: fakes);
        await tester.pumpAndSettle();
        await tester.tap(byTestId(VotesTestIds.unreadableVotesDiscard));
        await tester.pumpAndSettle();

        await tester.tap(byTestId(VotesTestIds.unreadableVotesConfirm));
        await tester.pumpAndSettle();

        expect(byTestId(VotesTestIds.unreadableVotes), findsNothing);
        expect(byTestId(VotesTestIds.unreadableVotesDialog), findsNothing);
        expect(fakes.outbox.unreadableSnapshot(), isEmpty);
        expect(fakes.outbox.snapshot().map((entry) => entry.vote), [
          _first.vote,
        ]);
        await endApp(tester, providers);
      });

      testWidgets(
        'says why when they could not be deleted, keeps them, and lets the '
        'user try again',
        (tester) async {
          final fakes = createFakes()
            ..outbox.seedUnreadable(user, 'k1')
            ..outbox.discardFailure = storageWriteFailed();
          final providers = await _pumpPending(tester, fakes: fakes);
          await tester.pumpAndSettle();
          await tester.tap(byTestId(VotesTestIds.unreadableVotesDiscard));
          await tester.pumpAndSettle();

          await tester.tap(byTestId(VotesTestIds.unreadableVotesConfirm));
          await tester.pumpAndSettle();

          expect(
            _within(
              VotesTestIds.unreadableVotesError,
              find.text(en.votesPendingVotesDiscardFailed),
            ),
            findsOneWidget,
          );
          expect(fakes.outbox.unreadableSnapshot(), hasLength(1));

          fakes.outbox.discardFailure = null;
          await tester.tap(byTestId(VotesTestIds.unreadableVotesConfirm));
          await tester.pumpAndSettle();
          expect(byTestId(VotesTestIds.unreadableVotes), findsNothing);
          await endApp(tester, providers);
        },
      );
    });

    group('when the outbox cannot be read', () {
      testWidgets(
        'says why, with a way to try again, and shows the votes when it works',
        (tester) async {
          final fakes = createFakes()
            ..outbox.seed([_first])
            ..outbox.listFailure = storageReadFailed();
          final providers = await _pumpPending(tester, fakes: fakes);
          await tester.pumpAndSettle();

          expect(
            _within(
              VotesTestIds.pendingVotesError,
              find.text(en.coreErrorsStorageReadFailed),
            ),
            findsOneWidget,
          );

          fakes.outbox.listFailure = null;
          await tester.tap(byTestId(CoreTestIds.retryButton));
          await tester.pumpAndSettle();

          expect(byTestId(pendingVoteTestId(_r1)), findsOneWidget);
          await endApp(tester, providers);
        },
      );

      testWidgets(
        'sends the user to the lock screen, without a retry, when the app is '
        'locked',
        (tester) async {
          final providers = await _pumpPending(
            tester,
            app: TestApp(startsLocked: true),
          );
          await tester.pumpAndSettle();

          expect(providers.read(accessProvider), Access.locked);
          expect(byTestId(CoreTestIds.retryButton), findsNothing);
          await endApp(tester, providers);
        },
      );
    });

    testWidgets('asks the outbox again when the user pulls to refresh', (
      tester,
    ) async {
      final fakes = createFakes();
      final providers = await _pumpPending(tester, fakes: fakes);
      await tester.pumpAndSettle();
      expect(byTestId(VotesTestIds.pendingVotesEmpty), findsOneWidget);
      fakes.outbox.seed([_first]);

      // The pull ends when the frames are pumped: it is not awaited.
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pumpAndSettle();

      expect(byTestId(pendingVoteTestId(_r1)), findsOneWidget);
      await endApp(tester, providers);
    });

    testWidgets(
      'shows the banner area and, in the mock configuration, the demo switch',
      (tester) async {
        final providers = await _pumpPending(
          tester,
          app: TestApp(
            demoControls: DemoControls(
              network: FakeDemoNetwork(),
              accounts: const [],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(byTestId(VotesTestIds.pendingVotesEmpty), findsOneWidget);

        providers
            .read(connectivityStateProvider.notifier)
            .set(ConnectivityStatus.offline);
        await tester.pump();

        expect(
          _within(CoreTestIds.offlineBanner, find.text(en.coreBannerOffline)),
          findsOneWidget,
        );
        expect(byTestId(CoreTestIds.demoOfflineSwitch), findsOneWidget);
        await endApp(tester, providers);
      },
    );

    group('in each language', () {
      for (final locale in [const Locale('en'), const Locale('fr')]) {
        testWidgets(
          'is written in ${locale.languageCode}, rejection included',
          (tester) async {
            final l10n = l10nOf(locale);
            final fakes = createFakes()..outbox.seed([_first, _rejected]);
            final providers = await _pumpPending(
              tester,
              fakes: fakes,
              locale: locale,
            );
            await tester.pumpAndSettle();

            expect(find.text(l10n.votesPendingVotesWaiting), findsOneWidget);
            expect(find.text(l10n.votesPendingVotesRejected), findsOneWidget);
            expect(
              find.text(l10n.votesVotingReasonResolutionClosed),
              findsOneWidget,
            );
            expect(
              find.text(l10n.votesPendingVotesExplanation),
              findsOneWidget,
            );
            await endApp(tester, providers);
          },
        );
      }

      testWidgets(
        'shows the explanation of the page in French, with the text of the '
        'French resource',
        (tester) async {
          final providers = await _pumpPending(
            tester,
            locale: const Locale('fr'),
          );
          await tester.pumpAndSettle();

          expect(find.text(fr.votesPendingVotesExplanation), findsOneWidget);
          expect(
            fr.votesPendingVotesExplanation,
            isNot(en.votesPendingVotesExplanation),
          );
          await endApp(tester, providers);
        },
      );
    });
  });
}
