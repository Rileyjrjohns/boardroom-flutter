import 'dart:async';
import 'dart:ui' show SemanticsRole;

import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/presentation/components/meeting_row.dart';
import 'package:boardroom/features/meetings/presentation/screens/meetings_list_screen.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../../support/builders/builders.dart';
import '../../../support/presentation/test_app.dart';
import 'support/meetings_screen_support.dart';

// The meetings list over the real use cases and the fakes. The scenarios are
// the ones of MeetingsListScreen.test.tsx of the React Native app.

final List<MeetingSummary> _upcoming = meetingsOf(
  'u',
  7,
  MeetingPeriod.upcoming,
);
final List<MeetingSummary> _past = meetingsOf('p', 4, MeetingPeriod.past);

Finder _within(String id, Finder finder) =>
    find.descendant(of: byTestId(id), matching: finder);

Finder _row(String id) => byTestId(meetingRowTestId(id));

/// Mounts the list with the meetings of both periods on the server.
Future<({TestApp app, ProviderContainer providers})> _renderList(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  TestApp? given,
}) async {
  useShortWindow(tester);
  final app = given ?? TestApp(meetingsPageSize: testPageSize);
  app.fakes.meetings
    ..setMeetings(MeetingPeriod.upcoming, _upcoming)
    ..setMeetings(MeetingPeriod.past, _past);
  final providers = await pumpPagedScreen(
    tester,
    const MeetingsListScreen(),
    app: app,
    locale: locale,
  );
  return (app: app, providers: providers);
}

Future<void> _choose(WidgetTester tester, MeetingPeriod period) async {
  await tester.tap(byTestId(periodOptionTestId(period.value)));
  await tester.pumpAndSettle();
}

void main() {
  final en = l10nOf();
  late Formatters format;
  setUpAll(() async {
    await initializeDateFormatting();
    format = Formatters('en');
  });

  group('MeetingsListScreen', () {
    testWidgets(
      'shows a loading state, then the first page of the upcoming meetings, '
      'soonest first',
      (tester) async {
        final (:providers, app: _) = await _renderList(tester);
        expect(byTestId(MeetingsTestIds.meetingsLoading), findsOneWidget);

        await tester.pumpAndSettle();

        expect(shownIds(tester), ['u1', 'u2', 'u3']);
        expect(byTestId(MeetingsTestIds.meetingsLoading), findsNothing);
        await finish(tester, providers);
      },
    );

    testWidgets(
      'shows the title, the date and time and the location of each meeting',
      (tester) async {
        final (:providers, app: _) = await _renderList(tester);
        await tester.pumpAndSettle();

        final row = _row('u1');
        expect(
          find.descendant(of: row, matching: find.text('Meeting u1')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.text(format.dateTime(_upcoming.first.scheduledAt)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text('Room u1')),
          findsOneWidget,
        );
        await finish(tester, providers);
      },
    );

    testWidgets('marks each row as a button that opens the meeting', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (:providers, app: _) = await _renderList(tester);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(_row('u1')),
        isSemantics(isButton: true, hint: en.meetingsOpenHint),
      );
      expect(
        tester.getSize(_row('u1')).height,
        greaterThanOrEqualTo(AppSizes.touchTargetMin),
      );
      semantics.dispose();
      await finish(tester, providers);
    });

    testWidgets('opens the meeting that is tapped', (tester) async {
      useShortWindow(tester);
      final app = TestApp(meetingsPageSize: testPageSize);
      app.fakes.meetings.setMeetings(MeetingPeriod.upcoming, _upcoming);
      final (:providers, :opened) = await pumpInRouter(
        tester,
        const MeetingsListScreen(),
        app: app,
      );
      await tester.pumpAndSettle();

      await tester.tap(_row('u2'));
      await tester.pumpAndSettle();

      expect(opened, ['u2']);
      await finish(tester, providers);
    });

    group('the period', () {
      testWidgets(
        'is chosen with an accessible control: tabs that say which one is '
        'selected',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final (:providers, app: _) = await _renderList(tester);
          await tester.pumpAndSettle();

          final upcoming = tester.getSemantics(
            byTestId(periodOptionTestId(MeetingPeriod.upcoming.value)),
          );
          final past = tester.getSemantics(
            byTestId(periodOptionTestId(MeetingPeriod.past.value)),
          );
          expect(
            upcoming,
            isSemantics(label: en.meetingsPeriodUpcoming, isSelected: true),
          );
          expect(
            past,
            isSemantics(label: en.meetingsPeriodPast, isSelected: false),
          );
          expect(upcoming.getSemanticsData().role, SemanticsRole.tab);
          expect(
            tester
                .getSemantics(find.bySemanticsLabel(en.meetingsPeriodLabel))
                .getSemanticsData()
                .role,
            SemanticsRole.tabBar,
          );
          expect(
            tester
                .getSize(byTestId(periodOptionTestId(MeetingPeriod.past.value)))
                .height,
            greaterThanOrEqualTo(AppSizes.touchTargetMin),
          );
          semantics.dispose();
          await finish(tester, providers);
        },
      );

      testWidgets('switches to the past meetings, latest first, and back', (
        tester,
      ) async {
        final (:providers, app: _) = await _renderList(tester);
        await tester.pumpAndSettle();

        await _choose(tester, MeetingPeriod.past);

        expect(shownIds(tester), ['p1', 'p2', 'p3']);
        await _choose(tester, MeetingPeriod.upcoming);
        expect(shownIds(tester), ['u1', 'u2', 'u3']);
        await finish(tester, providers);
      });

      testWidgets('is remembered when the screen is left and shown again', (
        tester,
      ) async {
        final (:providers, app: _) = await _renderList(tester);
        await tester.pumpAndSettle();
        await _choose(tester, MeetingPeriod.past);

        await tester.pumpWidget(testHost(providers, const SizedBox.shrink()));
        await tester.pumpWidget(
          testHost(providers, const MeetingsListScreen()),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getSemantics(byTestId(periodOptionTestId('past'))),
          isNotNull,
        );
        expect(shownIds(tester), ['p1', 'p2', 'p3']);
        await finish(tester, providers);
      });
    });

    group('pagination', () {
      testWidgets(
        'loads the next page when the end of the list is reached, with the '
        'cursor of the page before',
        (tester) async {
          final (:providers, :app) = await _renderList(tester);
          await tester.pumpAndSettle();
          expect(app.fakes.meetings.listCalls, hasLength(1));

          await reachEnd(tester);

          expect(shownIds(tester), ['u1', 'u2', 'u3', 'u4', 'u5', 'u6']);
          expect(
            app.fakes.meetings.listCalls.map((call) => call.request.cursor),
            [null, 'u3'],
          );
          expect(
            app.fakes.meetings.listCalls.map((call) => call.request.limit),
            [testPageSize, testPageSize],
          );
          await finish(tester, providers);
        },
      );

      testWidgets(
        'ends the list with a message when there is no page left, and asks '
        'for nothing more',
        (tester) async {
          final (:providers, :app) = await _renderList(tester);
          await tester.pumpAndSettle();
          expect(byTestId(MeetingsTestIds.meetingsEnd), findsNothing);

          await reachEnd(tester);
          await reachEnd(tester);
          await tester.scrollUntilVisible(
            byTestId(MeetingsTestIds.meetingsEnd),
            200,
            scrollable: find.byType(Scrollable).last,
          );
          await reachEnd(tester);

          expect(shownIds(tester), contains('u7'));
          expect(find.text(en.meetingsEndOfList), findsOneWidget);
          expect(app.fakes.meetings.listCalls, hasLength(3));
          await finish(tester, providers);
        },
      );

      testWidgets('does not ask for a page while one is being loaded', (
        tester,
      ) async {
        final (:providers, :app) = await _renderList(tester);
        await tester.pumpAndSettle();
        final gate = Completer<void>();
        app.fakes.meetings.onRequest = () => gate.future;

        await tester.drag(meetingsListFinder, const Offset(0, -1000));
        await tester.drag(meetingsListFinder, const Offset(0, -1000));
        gate.complete();
        await tester.pumpAndSettle();

        expect(app.fakes.meetings.listCalls, hasLength(2));
        await finish(tester, providers);
      });

      const name =
          'says the next page could not be loaded, keeps the meetings, and '
          'loads it on retry';
      testWidgets(name, (tester) async {
        final (:providers, :app) = await _renderList(tester);
        await tester.pumpAndSettle();
        app.fakes.meetings.failure = unexpected();

        await reachEnd(tester);

        expect(byTestId(MeetingsTestIds.meetingsLoadMoreError), findsOneWidget);
        expect(find.text(en.coreErrorsUnexpected), findsOneWidget);
        expect(shownIds(tester), ['u1', 'u2', 'u3']);
        // The user decides when to try again: reaching the end again does not.
        final callsBefore = app.fakes.meetings.listCalls.length;
        await reachEnd(tester);
        expect(app.fakes.meetings.listCalls, hasLength(callsBefore));

        app.fakes.meetings.failure = null;
        await tester.tap(
          _within(
            MeetingsTestIds.meetingsLoadMoreError,
            byTestId(CoreTestIds.retryButton),
          ),
        );
        await tester.pumpAndSettle();

        expect(shownIds(tester), contains('u4'));
        expect(byTestId(MeetingsTestIds.meetingsLoadMoreError), findsNothing);
        await finish(tester, providers);
      });
    });

    group('pull to refresh', () {
      testWidgets(
        'reads the list again, and shows what changed on the server',
        (tester) async {
          final (:providers, :app) = await _renderList(tester);
          await tester.pumpAndSettle();
          app.fakes.meetings.setMeetings(
            MeetingPeriod.upcoming,
            _upcoming.sublist(1),
          );

          await pullToRefresh(tester);

          expect(shownIds(tester), ['u2', 'u3', 'u4']);
          expect(app.fakes.meetings.listCalls, hasLength(2));
          await finish(tester, providers);
        },
      );

      testWidgets(
        'shows the refresh indicator while it lasts, and not afterwards',
        (tester) async {
          final (:providers, :app) = await _renderList(tester);
          await tester.pumpAndSettle();
          final gate = Completer<void>();
          app.fakes.meetings.onRequest = () => gate.future;

          await tester.fling(meetingsListFinder, const Offset(0, 400), 1000);
          await tester.pump(const Duration(seconds: 1));
          expect(find.byType(RefreshProgressIndicator), findsOneWidget);

          gate.complete();
          await tester.pumpAndSettle();

          expect(find.byType(RefreshProgressIndicator), findsNothing);
          await finish(tester, providers);
        },
      );

      testWidgets('keeps the meetings and says so when the refresh fails', (
        tester,
      ) async {
        final (:providers, :app) = await _renderList(tester);
        await tester.pumpAndSettle();
        app.fakes.meetings.failure = unexpected();

        await pullToRefresh(tester);

        expect(byTestId(CoreTestIds.refreshError), findsOneWidget);
        expect(find.text(en.coreErrorsUnexpected), findsOneWidget);
        expect(shownIds(tester), ['u1', 'u2', 'u3']);
        await finish(tester, providers);
      });
    });

    group('the states of a list', () {
      testWidgets(
        'shows the empty state of the period when there is no meeting',
        (tester) async {
          useShortWindow(tester);
          final app = TestApp(meetingsPageSize: testPageSize);
          app.fakes.meetings
            ..setMeetings(MeetingPeriod.upcoming, [])
            ..setMeetings(MeetingPeriod.past, _past);
          final providers = await pumpPagedScreen(
            tester,
            const MeetingsListScreen(),
            app: app,
          );
          await tester.pumpAndSettle();

          expect(byTestId(MeetingsTestIds.meetingsEmpty), findsOneWidget);
          expect(find.text(en.meetingsEmptyUpcoming), findsOneWidget);
          await _choose(tester, MeetingPeriod.past);
          expect(shownIds(tester), ['p1', 'p2', 'p3']);
          expect(byTestId(MeetingsTestIds.meetingsEmpty), findsNothing);
          await finish(tester, providers);
        },
      );

      testWidgets('shows the empty state of the past period', (tester) async {
        useShortWindow(tester);
        final app = TestApp(meetingsPageSize: testPageSize);
        app.fakes.meetings
          ..setMeetings(MeetingPeriod.upcoming, _upcoming)
          ..setMeetings(MeetingPeriod.past, []);
        final providers = await pumpPagedScreen(
          tester,
          const MeetingsListScreen(),
          app: app,
        );
        await tester.pumpAndSettle();

        await _choose(tester, MeetingPeriod.past);

        expect(find.text(en.meetingsEmptyPast), findsOneWidget);
        await finish(tester, providers);
      });

      testWidgets(
        'shows an error with a way to retry, and the list when the retry '
        'succeeds',
        (tester) async {
          useShortWindow(tester);
          final app = TestApp(meetingsPageSize: testPageSize);
          app.fakes.meetings
            ..setMeetings(MeetingPeriod.upcoming, _upcoming)
            ..failure = unexpected();
          final providers = await pumpPagedScreen(
            tester,
            const MeetingsListScreen(),
            app: app,
          );
          await tester.pumpAndSettle();

          expect(byTestId(MeetingsTestIds.meetingsError), findsOneWidget);
          expect(
            _within(
              MeetingsTestIds.meetingsError,
              find.text(en.coreErrorsUnexpected),
            ),
            findsOneWidget,
          );
          // A fault of the server is worth trying again before giving up: the
          // first call and two retries.
          expect(app.fakes.meetings.listCalls, hasLength(3));

          app.fakes.meetings.failure = null;
          await tester.tap(
            _within(
              MeetingsTestIds.meetingsError,
              byTestId(CoreTestIds.retryButton),
            ),
          );
          await tester.pumpAndSettle();

          expect(shownIds(tester), ['u1', 'u2', 'u3']);
          expect(byTestId(MeetingsTestIds.meetingsError), findsNothing);
          await finish(tester, providers);
        },
      );

      testWidgets(
        'does not retry, and ends the session, when trying again cannot help',
        (tester) async {
          useShortWindow(tester);
          final app = TestApp(meetingsPageSize: testPageSize);
          app.fakes.meetings
            ..setMeetings(MeetingPeriod.upcoming, _upcoming)
            ..failure = unauthorized();
          final providers = await pumpPagedScreen(
            tester,
            const MeetingsListScreen(),
            app: app,
          );
          // The list stays mounted here and waits, with no one to ask, for an
          // app that is open again: it never settles.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(
            providers.read(accessControllerProvider).sessionEndedBy,
            'unauthorized',
          );
          expect(accessOf(providers), Access.signedOut);
          expect(app.fakes.meetings.listCalls, hasLength(1));
          await finish(tester, providers);
        },
      );

      testWidgets(
        'shows the network error of a list that was never loaded, with a retry',
        (tester) async {
          useShortWindow(tester);
          final app = TestApp(meetingsPageSize: testPageSize);
          app.fakes.meetings.setMeetings(MeetingPeriod.upcoming, _upcoming);
          app.fakes.network.goOffline();
          final providers = await pumpPagedScreen(
            tester,
            const MeetingsListScreen(),
            app: app,
          );
          await tester.pumpAndSettle();

          expect(
            _within(
              MeetingsTestIds.meetingsError,
              find.text(en.coreErrorsNetworkUnavailable),
            ),
            findsOneWidget,
          );

          app.fakes.network.goOnline();
          await tester.tap(
            _within(
              MeetingsTestIds.meetingsError,
              byTestId(CoreTestIds.retryButton),
            ),
          );
          await tester.pumpAndSettle();
          expect(_row('u1'), findsOneWidget);
          await finish(tester, providers);
        },
      );
    });

    group('saved data', () {
      testWidgets('shows no banner while the data comes from the server', (
        tester,
      ) async {
        final (:providers, app: _) = await _renderList(tester);
        await tester.pumpAndSettle();

        expect(byTestId(CoreTestIds.staleBanner), findsNothing);
        await finish(tester, providers);
      });

      testWidgets(
        'says since when the data is a saved copy, when the network is down '
        'after a first load',
        (tester) async {
          final (:providers, :app) = await _renderList(tester);
          await tester.pumpAndSettle();
          app.fakes.clock.advance(60000);
          app.fakes.network.goOffline();

          await pullToRefresh(tester);

          expect(
            _within(
              CoreTestIds.staleBanner,
              find.text(en.coreStatesStaleData(format.dateTime(now))),
            ),
            findsOneWidget,
          );
          expect(shownIds(tester), ['u1', 'u2', 'u3']);
          expect(byTestId(CoreTestIds.refreshError), findsNothing);
          await finish(tester, providers);
        },
      );

      testWidgets('takes the banner away when the server answers again', (
        tester,
      ) async {
        final (:providers, :app) = await _renderList(tester);
        await tester.pumpAndSettle();
        app.fakes.network.goOffline();
        await pullToRefresh(tester);
        expect(byTestId(CoreTestIds.staleBanner), findsOneWidget);

        app.fakes.network.goOnline();
        await pullToRefresh(tester);

        expect(byTestId(CoreTestIds.staleBanner), findsNothing);
        await finish(tester, providers);
      });

      testWidgets('says the device is offline, apart from the saved copy', (
        tester,
      ) async {
        final (:providers, app: _) = await _renderList(tester);
        await tester.pumpAndSettle();

        providers
            .read(connectivityStateProvider.notifier)
            .set(ConnectivityStatus.offline);
        await tester.pump();

        expect(byTestId(CoreTestIds.offlineBanner), findsOneWidget);
        expect(byTestId(CoreTestIds.staleBanner), findsNothing);
        await finish(tester, providers);
      });
    });

    group('in each language', () {
      for (final locale in AppLocalizations.supportedLocales) {
        testWidgets('shows the control, the dates and the states in '
            '${locale.languageCode}', (tester) async {
          final texts = l10nOf(locale);
          final (:providers, app: _) = await _renderList(
            tester,
            locale: locale,
          );
          await tester.pumpAndSettle();

          expect(find.text(texts.meetingsPeriodUpcoming), findsOneWidget);
          expect(
            _within(
              meetingRowTestId('u1'),
              find.text(
                Formatters(locale.languageCode)
                    .dateTime(_upcoming.first.scheduledAt),
              ),
            ),
            findsOneWidget,
          );
          await finish(tester, providers);
        });
      }

      testWidgets(
        'translates the screen into French: the control, the empty state, the '
        'date',
        (tester) async {
          final fr = l10nOf(const Locale('fr'));
          useShortWindow(tester);
          final app = TestApp(meetingsPageSize: testPageSize);
          app.fakes.meetings
            ..setMeetings(MeetingPeriod.upcoming, _upcoming)
            ..setMeetings(MeetingPeriod.past, []);
          final providers = await pumpPagedScreen(
            tester,
            const MeetingsListScreen(),
            app: app,
            locale: const Locale('fr'),
          );
          await tester.pumpAndSettle();

          expect(find.text(fr.meetingsPeriodUpcoming), findsOneWidget);
          expect(find.text(fr.meetingsPeriodPast), findsOneWidget);
          expect(
            _within(meetingRowTestId('u1'), find.textContaining('mars')),
            findsOneWidget,
          );

          await _choose(tester, MeetingPeriod.past);
          expect(find.text(fr.meetingsEmptyPast), findsOneWidget);
          await finish(tester, providers);
        },
      );
    });

    group('for the screen reader', () {
      testWidgets('tells what the list waits for while it loads', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final (:providers, app: _) = await _renderList(tester);

        expect(find.bySemanticsLabel(en.meetingsLoading), findsOneWidget);

        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(en.meetingsLoading), findsNothing);
        semantics.dispose();
        await finish(tester, providers);
      });

      testWidgets(
        'tells that more is loading at the end of the list, with a name',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final (:providers, :app) = await _renderList(tester);
          await tester.pumpAndSettle();
          final gate = Completer<void>();
          app.fakes.meetings.onRequest = () => gate.future;

          await tester.drag(meetingsListFinder, const Offset(0, -1000));
          await tester.pump(const Duration(milliseconds: 100));

          expect(byTestId(MeetingsTestIds.meetingsLoadingMore), findsOneWidget);
          expect(find.bySemanticsLabel(en.meetingsLoadingMore), findsOneWidget);
          gate.complete();
          await tester.pumpAndSettle();
          semantics.dispose();
          await finish(tester, providers);
        },
      );

      testWidgets('announces on iOS that it is refreshing', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final announced = <Object?>[];
        tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility,
              (message) async {
                announced.add(message);
                return null;
              },
            );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger
              .setMockDecodedMessageHandler<dynamic>(
                SystemChannels.accessibility,
                null,
              ),
        );
        final (:providers, app: _) = await _renderList(tester);
        await tester.pumpAndSettle();
        announced.clear();

        await pullToRefresh(tester);

        debugDefaultTargetPlatformOverride = null;
        expect(announced.toString(), contains(en.coreStatesRefreshing));
        await finish(tester, providers);
      });
    });

    testWidgets(
      'keys the rows by meeting and renders them with the list of the platform',
      (tester) async {
        final (:providers, app: _) = await _renderList(tester);
        await tester.pumpAndSettle();

        final rows = tester.widgetList<MeetingRow>(
          find.byType(MeetingRow, skipOffstage: false),
        );

        expect(rows.map((row) => row.key), [
          const ValueKey('u1'),
          const ValueKey('u2'),
          const ValueKey('u3'),
        ]);
        expect(tester.widget<CustomScrollView>(meetingsListFinder), isNotNull);
        await finish(tester, providers);
      },
    );
  });
}
