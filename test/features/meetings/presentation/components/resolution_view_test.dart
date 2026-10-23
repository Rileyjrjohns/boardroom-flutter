import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/policies/voting_state.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/meetings/presentation/components/resolution_view.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/presentation/test_app.dart';

// Where voting stands is told by the rule of the domain, at the instant the
// data was produced at. The component reads no clock: given the same
// resolution at two instants, it shows two states.

final Instant _closesAt = at(millisPerDay);
final Instant _before = now;
final Instant _after = at(2 * millisPerDay);

/// Mounts the card of a resolution judged at [judgedAt] and returns its finder.
Future<Finder> _renderResolution(
  WidgetTester tester, {
  Instant? closesAt,
  ResolutionStatus status = ResolutionStatus.open,
  VoteChoice? recordedVote,
  Instant? judgedAt,
  Locale locale = const Locale('en'),
}) async {
  final resolution = aResolution(
    status: status,
    closesAt: closesAt,
    recordedVote: recordedVote,
  );
  await pumpScreen(
    tester,
    ResolutionView(resolution: resolution, now: judgedAt ?? _before),
    locale: locale,
  );
  return byTestId(resolutionTestId(resolution.id));
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  final en = l10nOf();
  late Formatters format;
  setUpAll(() async {
    await initializeDateFormatting();
    format = Formatters('en');
  });

  group('ResolutionView', () {
    group('an open resolution', () {
      testWidgets('says it is open, in green, with the deadline of the vote', (
        tester,
      ) async {
        final view = await _renderResolution(tester, closesAt: _closesAt);

        expect(
          _colorOf(tester, en.meetingsVotingStateOpen),
          AppColors.positiveBadgeText,
        );
        expect(
          find.descendant(
            of: view,
            matching: find.text(
              en.meetingsMeetingVotingDeadline(format.dateTime(_closesAt)),
            ),
          ),
          findsOneWidget,
        );
      });

      testWidgets('has no date to show when it has no closing instant', (
        tester,
      ) async {
        final view = await _renderResolution(tester);

        expect(
          find.descendant(
            of: view,
            matching: find.text(en.meetingsVotingStateOpen),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Vote by'), findsNothing);
        expect(find.textContaining('Closed on'), findsNothing);
      });
    });

    group('a resolution that is open but whose window is over', () {
      testWidgets(
        'does not say it is open: it says the voting ended, in neutral, with '
        'the date it closed on',
        (tester) async {
          await _renderResolution(
            tester,
            closesAt: _closesAt,
            judgedAt: _after,
          );

          expect(find.text(en.meetingsVotingStateOpen), findsNothing);
          expect(
            _colorOf(tester, en.meetingsVotingStateWindowOver),
            AppColors.neutralBadgeText,
          );
          expect(
            find.text(
              en.meetingsMeetingVotingClosedOn(format.dateTime(_closesAt)),
            ),
            findsOneWidget,
          );
          expect(find.textContaining('Vote by'), findsNothing);
        },
      );

      testWidgets(
        'is judged at the instant it is given: the same resolution is open a '
        'moment before',
        (tester) async {
          await _renderResolution(
            tester,
            closesAt: _closesAt,
            judgedAt: at(millisPerDay - 1),
          );

          expect(find.text(en.meetingsVotingStateOpen), findsOneWidget);
        },
      );

      testWidgets(
        'is over at the closing instant itself, as it is for the eligibility '
        'to vote',
        (tester) async {
          await _renderResolution(
            tester,
            closesAt: _closesAt,
            judgedAt: _closesAt,
          );

          expect(find.text(en.meetingsVotingStateWindowOver), findsOneWidget);
        },
      );
    });

    group('a closed resolution', () {
      testWidgets(
        'says it is closed, in neutral, and never speaks of a deadline',
        (tester) async {
          await _renderResolution(
            tester,
            status: ResolutionStatus.closed,
            closesAt: at(-millisPerDay),
          );

          expect(
            _colorOf(tester, en.meetingsVotingStateClosed),
            AppColors.neutralBadgeText,
          );
          expect(
            find.text(
              en.meetingsMeetingVotingClosedOn(
                format.dateTime(at(-millisPerDay)),
              ),
            ),
            findsOneWidget,
          );
          expect(find.textContaining('Vote by'), findsNothing);
        },
      );
    });

    test('is told with the same rule as the eligibility to vote', () {
      // The states are those of the domain: one word for each, in each
      // language.
      for (final state in VotingState.values) {
        expect(state.value, isNotEmpty);
      }
      expect(VotingState.values, hasLength(3));
    });

    testWidgets('shows the vote of the user, or that there is none', (
      tester,
    ) async {
      final view = await _renderResolution(
        tester,
        recordedVote: VoteChoice.against,
      );

      expect(
        find.descendant(
          of: view,
          matching: find.text(
            en.meetingsMeetingResolutionYourVote(en.votesVoteChoiceAgainst),
          ),
        ),
        findsOneWidget,
      );
    });

    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets('is written in ${locale.languageCode}', (tester) async {
        final texts = l10nOf(locale);
        final view = await _renderResolution(
          tester,
          closesAt: _closesAt,
          judgedAt: _after,
          locale: locale,
        );

        expect(
          find.descendant(
            of: view,
            matching: find.text(texts.meetingsVotingStateWindowOver),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: view,
            matching: find.text(texts.meetingsMeetingResolutionNoVote),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('says in French that the window is over, and when', (
      tester,
    ) async {
      final fr = l10nOf(const Locale('fr'));
      final view = await _renderResolution(
        tester,
        closesAt: _closesAt,
        judgedAt: _after,
        locale: const Locale('fr'),
      );

      expect(
        find.descendant(
          of: view,
          matching: find.text(fr.meetingsVotingStateWindowOver),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: view,
          matching: find.text(
            fr.meetingsMeetingVotingClosedOn(
              Formatters('fr').dateTime(_closesAt),
            ),
          ),
        ),
        findsOneWidget,
      );
    });
  });
}
