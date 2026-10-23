import 'dart:async';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/query/query_lifetime.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/presentation/screens/meetings_list_screen.dart';
import 'package:boardroom/features/meetings/presentation/state/meetings_list.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/presentation/test_app.dart';
import 'support/meetings_screen_support.dart';

// The cache policy of the list as the user lives it: what a pull to refresh
// costs when several pages are loaded, what coming back to a period costs, and
// what one period's refresh looks like on the other. The scenarios are the ones
// of listCache.test.tsx of the React Native app.

final List<MeetingSummary> _upcoming = meetingsOf(
  'u',
  7,
  MeetingPeriod.upcoming,
);
final List<MeetingSummary> _past = meetingsOf('p', 4, MeetingPeriod.past);

/// Mounts the list with the meetings of both periods on the server.
Future<({TestApp app, ProviderContainer providers})> _renderList(
  WidgetTester tester,
) async {
  useShortWindow(tester);
  final app = TestApp(meetingsPageSize: testPageSize);
  app.fakes.meetings
    ..setMeetings(MeetingPeriod.upcoming, _upcoming)
    ..setMeetings(MeetingPeriod.past, _past);
  final providers = await pumpPagedScreen(
    tester,
    const MeetingsListScreen(),
    app: app,
  );
  return (app: app, providers: providers);
}

/// The meetings the upcoming list holds, whether they are built or not.
List<String> _loaded(ProviderContainer providers, MeetingPeriod period) => [
  for (final meeting
      in providers.read(meetingsListProvider(period)).requireValue.meetings)
    meeting.id,
];

Future<({TestApp app, ProviderContainer providers})> _loadThreePages(
  WidgetTester tester,
) async {
  final rendered = await _renderList(tester);
  await tester.pumpAndSettle();
  await reachEnd(tester);
  await reachEnd(tester);
  expect(_loaded(rendered.providers, MeetingPeriod.upcoming), hasLength(7));
  expect(rendered.app.fakes.meetings.listCalls, hasLength(3));
  return rendered;
}

Future<void> _choose(WidgetTester tester, MeetingPeriod period) async {
  await tester.tap(byTestId(periodOptionTestId(period.value)));
  await tester.pump();
}

void main() {
  group('a pull to refresh with several pages loaded', () {
    testWidgets(
      'starts again from the first page: one request, not one for each page '
      'loaded',
      (tester) async {
        final (:providers, :app) = await _loadThreePages(tester);

        await refreshFromAnywhere(tester);

        expect(app.fakes.meetings.listCalls, hasLength(4));
        expect(app.fakes.meetings.listCalls[3].request.cursor, isNull);
        expect(shownIds(tester), ['u1', 'u2', 'u3']);
        await finish(tester, providers);
      },
    );

    testWidgets(
      'shows what changed on the server in the first page, and can load the '
      'next ones again',
      (tester) async {
        final (:providers, :app) = await _loadThreePages(tester);
        app.fakes.meetings.setMeetings(
          MeetingPeriod.upcoming,
          _upcoming.sublist(1),
        );

        await refreshFromAnywhere(tester);
        expect(_loaded(providers, MeetingPeriod.upcoming), ['u2', 'u3', 'u4']);
        await reachEnd(tester);

        expect(_loaded(providers, MeetingPeriod.upcoming), [
          'u2',
          'u3',
          'u4',
          'u5',
          'u6',
          'u7',
        ]);
        await finish(tester, providers);
      },
    );

    testWidgets(
      'starts again from the first page when a failed refresh is tried again',
      (tester) async {
        final (:providers, :app) = await _loadThreePages(tester);
        app.fakes.meetings.failure = unexpected();
        await refreshFromAnywhere(tester);
        expect(byTestId(CoreTestIds.refreshError), findsOneWidget);
        app.fakes.meetings.failure = null;
        final callsBefore = app.fakes.meetings.listCalls.length;

        await tester.tap(
          find.descendant(
            of: byTestId(CoreTestIds.refreshError),
            matching: byTestId(CoreTestIds.retryButton),
          ),
        );
        await tester.pumpAndSettle();

        expect(byTestId(CoreTestIds.refreshError), findsNothing);
        expect(app.fakes.meetings.listCalls, hasLength(callsBefore + 1));
        expect(app.fakes.meetings.listCalls.last.request.cursor, isNull);
        await finish(tester, providers);
      },
    );
  });

  group('coming back to a period', () {
    Future<({TestApp app, ProviderContainer providers})> leaveAndComeBack(
      WidgetTester tester,
      Duration waitBeforeComingBack,
    ) async {
      final rendered = await _renderList(tester);
      await tester.pumpAndSettle();
      await _choose(tester, MeetingPeriod.past);
      await tester.pumpAndSettle();
      expect(shownIds(tester), ['p1', 'p2', 'p3']);
      await tester.pump(waitBeforeComingBack);

      await _choose(tester, MeetingPeriod.upcoming);
      return rendered;
    }

    testWidgets(
      'shows it at once and asks nothing while what it holds is current',
      (tester) async {
        final (:providers, :app) = await leaveAndComeBack(
          tester,
          queryStaleTime ~/ 2,
        );

        expect(shownIds(tester), ['u1', 'u2', 'u3']);
        await tester.pump();
        expect(app.fakes.meetings.listCalls, hasLength(2));
        await finish(tester, providers);
      },
    );

    testWidgets(
      'shows it at once and checks with the server in the background once it '
      'is not current',
      (tester) async {
        final (:providers, :app) = await leaveAndComeBack(
          tester,
          queryStaleTime * 2,
        );

        expect(shownIds(tester), ['u1', 'u2', 'u3']);
        await tester.pumpAndSettle();
        expect(app.fakes.meetings.listCalls, hasLength(3));
        expect(app.fakes.meetings.listCalls[2].period, MeetingPeriod.upcoming);
        await finish(tester, providers);
      },
    );
  });

  group('the refresh of one period', () {
    testWidgets('does not show on the other period', (tester) async {
      final (:providers, :app) = await _renderList(tester);
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      app.fakes.meetings.onRequest = () => gate.future;

      await tester.fling(meetingsListFinder, const Offset(0, 400), 1000);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);

      await _choose(tester, MeetingPeriod.past);
      await tester.pump();
      expect(find.byType(RefreshProgressIndicator), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(shownIds(tester), ['p1', 'p2', 'p3']);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      await finish(tester, providers);
    });

    testWidgets(
      'keeps one list for each period, so that the other starts from its own '
      'first rows',
      (tester) async {
        final (:providers, app: _) = await _renderList(tester);
        await tester.pumpAndSettle();
        await reachEnd(tester);
        expect(_loaded(providers, MeetingPeriod.upcoming), hasLength(6));

        await _choose(tester, MeetingPeriod.past);
        await tester.pumpAndSettle();

        expect(shownIds(tester), ['p1', 'p2', 'p3']);
        await finish(tester, providers);
      },
    );
  });
}
