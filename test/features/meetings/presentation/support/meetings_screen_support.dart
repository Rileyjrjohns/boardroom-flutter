import 'dart:async';

import 'package:boardroom/core/presentation/navigation/routes.dart';
import 'package:boardroom/core/presentation/theme/app_theme.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/presentation/test_app.dart';

// Test support, not production code: what the tests of the meetings screens
// share.

/// The page size of the tests of the list: small, so that a few meetings make
/// several pages.
const int testPageSize = 3;

/// `pumpScreen` for an app built with
/// `TestApp(meetingsPageSize: testPageSize)`.
Future<ProviderContainer> pumpPagedScreen(
  WidgetTester tester,
  Widget screen, {
  required TestApp app,
  Locale locale = const Locale('en'),
}) async {
  final providers = app.providers();
  await tester.pumpWidget(testHost(providers, screen, locale: locale));
  return providers;
}

/// [count] meetings of one period, one per day, named `<prefix>1`,
/// `<prefix>2`... The first is the nearest to the instant of the tests:
/// upcoming ones go forward from it, past ones backward.
List<MeetingSummary> meetingsOf(
  String prefix,
  int count,
  MeetingPeriod period,
) => [
  for (var day = 1; day <= count; day++)
    aMeetingSummary(
      id: aMeetingId('$prefix$day'),
      title: 'Meeting $prefix$day',
      location: 'Room $prefix$day',
      scheduledAt: at(
        (period == MeetingPeriod.upcoming ? day : -day) * millisPerDay,
      ),
    ),
];

/// The finder of the scrolling list of the screen.
Finder get meetingsListFinder => byTestId(MeetingsTestIds.meetingsList);

/// The finder of the rows built, in the order of the tree.
Finder get meetingRows => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith(meetingRowTestIdPrefix);
}, skipOffstage: false);

/// The ids of the meetings shown, in the order shown.
List<String> shownIds(WidgetTester tester) => [
  for (final row in tester.widgetList(meetingRows))
    (row.key! as ValueKey<String>).value.substring(
      meetingRowTestIdPrefix.length,
    ),
];

/// A phone-sized window, short enough that three rows overflow the list: the
/// list asks for its next page only when the end is near, and a list whose end
/// is in view from the start asks at once.
void useShortWindow(WidgetTester tester, {double height = 250}) {
  tester.view.physicalSize = Size(400, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Scrolls the list to its end, the way the user does, and lets the page that
/// is asked for arrive.
Future<void> reachEnd(WidgetTester tester) async {
  await tester.drag(meetingsListFinder, const Offset(0, -1000));
  await tester.pumpAndSettle();
}

/// The pull down of the user on [finder], and the refresh that follows.
///
/// A screen that is left spinning (the session ended under it) never settles:
/// pass `settle: false` to let a few frames pass instead.
Future<void> pullToRefresh(
  WidgetTester tester, {
  Finder? finder,
  bool settle = true,
}) async {
  await tester.fling(finder ?? meetingsListFinder, const Offset(0, 400), 1000);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The refresh of a list that is scrolled down: a pull works from the top
/// only, so the list goes back to the top and the indicator is shown the way
/// the pull does.
Future<void> refreshFromAnywhere(WidgetTester tester) async {
  tester
      .state<ScrollableState>(
        find.descendant(
          of: meetingsListFinder,
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .jumpTo(0);
  await tester.pump();
  unawaited(
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
  );
  await tester.pumpAndSettle();
}

/// Ends a test that mounted a screen: the queries keep timers, which die with
/// the container.
Future<void> finish(WidgetTester tester, ProviderContainer providers) async {
  await tester.pumpWidget(const SizedBox.shrink());
  providers.dispose();
}

/// The access the container holds.
Access accessOf(ProviderContainer providers) => providers.read(accessProvider);

/// Mounts [screen] in an app with a router that has the routes the screen
/// opens, and records the location of each route it is sent to.
Future<({ProviderContainer providers, List<String> opened})> pumpInRouter(
  WidgetTester tester,
  Widget screen, {
  required TestApp app,
}) async {
  final opened = <String>[];
  final providers = app.providers();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: AppRoutes.meetings.path,
        builder: (_, _) => Scaffold(body: screen),
      ),
      GoRoute(
        path: AppRoutes.meetingDetail.path,
        builder: (_, state) {
          opened.add(state.pathParameters[RouteParams.meetingId]!);
          return const SizedBox.shrink();
        },
      ),
      GoRoute(
        path: AppRoutes.document.path,
        builder: (_, state) {
          opened.add(state.pathParameters[RouteParams.documentId]!);
          return const SizedBox.shrink();
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: providers,
      child: MaterialApp.router(
        routerConfig: router,
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  return (providers: providers, opened: opened);
}

/// Locks the app the way coming back after the grace period does: the lock is
/// an object of the use cases that the fakes do not share, so it is asked of
/// the use case that sets it.
Future<void> lockApp(TestApp app) async {
  await app.useCases.evaluateAppLock.execute(
    backgroundedAt: at(-millisPerHour),
  );
}
