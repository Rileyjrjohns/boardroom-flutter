import 'dart:async';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/presentation/screens/meeting_detail_screen.dart';
import 'package:boardroom/features/meetings/presentation/screens/meetings_list_screen.dart';
import 'package:boardroom/features/meetings/presentation/state/meeting_query.dart';
import 'package:boardroom/features/meetings/presentation/state/meetings_list.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/presentation/test_app.dart';
import 'support/meetings_screen_support.dart';

// What the screens do when something that was loaded cannot be loaded again. A
// failure that asking again cannot fix is final for the screen: it shows the
// error and never the data it had before. One that ends the session also tells
// the access where the user goes (the sign-in or the lock screen), and the
// data of the user goes with the screens, which the router removes. One that
// can pass leaves the data and offers the retry. The scenarios are the ones of
// failures.test.tsx of the React Native app.

final List<MeetingSummary> _upcoming = meetingsOf(
  'u',
  7,
  MeetingPeriod.upcoming,
);
final Meeting _meeting = aMeeting();

Finder _within(String id, Finder finder) =>
    find.descendant(of: byTestId(id), matching: finder);

/// Mounts the list with the upcoming meetings on the server.
Future<({TestApp app, ProviderContainer providers})> _renderList(
  WidgetTester tester,
) async {
  useShortWindow(tester);
  final app = TestApp(meetingsPageSize: testPageSize);
  app.fakes.meetings.setMeetings(MeetingPeriod.upcoming, _upcoming);
  final providers = await pumpPagedScreen(
    tester,
    const MeetingsListScreen(),
    app: app,
  );
  return (app: app, providers: providers);
}

Future<({TestApp app, ProviderContainer providers})> _renderDetail(
  WidgetTester tester,
) async {
  final app = TestApp(meetingsPageSize: testPageSize);
  app.fakes.meetings.addMeeting(_meeting);
  final providers = await pumpScreen(
    tester,
    MeetingDetailScreen(meetingId: _meeting.id),
    app: app,
  );
  return (app: app, providers: providers);
}

/// The ways the session can end under a screen that is showing data: the code,
/// and what makes it end.
final List<(String, Future<void> Function(TestApp app))> _sessionEndings = [
  ('unauthorized', (app) async => app.fakes.meetings.failure = unauthorized()),
  ('appLocked', lockApp),
  ('notAuthenticated', (app) async => app.fakes.auth.session = null),
  ('sessionExpired', (app) async => app.fakes.clock.advance(2 * millisPerHour)),
  (
    'sessionChanged',
    (app) async => app.fakes.meetings.onRequest = () {
      app.fakes.auth.session = aSession(user: aUser(id: aUserId('user-9')));
    },
  ),
];

/// Where the user goes when the session ends, for each way it ends.
Access _accessAfter(String code) =>
    code == 'appLocked' ? Access.locked : Access.signedOut;

/// Lets the failure reach the access: the screen stays mounted and waits for an
/// app that is open again, so it never settles.
Future<void> _letItEnd(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// What the router does when the session ends: the screens of the open app are
/// removed. These tests mount the screen without a router.
Future<void> _routerRemovesTheScreen(
  WidgetTester tester,
  ProviderContainer providers,
) async {
  await tester.pumpWidget(testHost(providers, const SizedBox.shrink()));
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pump(const Duration(milliseconds: 10));
}

/// Whether the list of the upcoming meetings is still held in memory.
bool _listIsInMemory(ProviderContainer providers) =>
    providers.exists(meetingsListProvider(MeetingPeriod.upcoming));

void main() {
  final en = l10nOf();

  group('when the session ends while a list is on the screen', () {
    for (final (code, end) in _sessionEndings) {
      testWidgets(
        'sends the user to the screen that fits and empties the cache: $code',
        (tester) async {
          final (:providers, :app) = await _renderList(tester);
          await tester.pumpAndSettle();
          expect(accessOf(providers), Access.unlocked);

          await end(app);
          await pullToRefresh(tester, settle: false);
          await _letItEnd(tester);

          expect(accessOf(providers), _accessAfter(code));
          expect(providers.read(accessControllerProvider).sessionEndedBy, code);
          await _routerRemovesTheScreen(tester, providers);
          expect(_listIsInMemory(providers), isFalse);
          await finish(tester, providers);
        },
      );
    }

    testWidgets('does not ask again once the session has ended', (
      tester,
    ) async {
      final (:providers, :app) = await _renderList(tester);
      await tester.pumpAndSettle();
      app.fakes.meetings.failure = unauthorized();

      await pullToRefresh(tester, settle: false);
      await _letItEnd(tester);
      expect(accessOf(providers), Access.signedOut);
      final calls = app.fakes.meetings.listCalls.length;
      await tester.pump(const Duration(hours: 10));

      expect(app.fakes.meetings.listCalls, hasLength(calls));
      await finish(tester, providers);
    });

    testWidgets('does the same when the next page is the one that is refused', (
      tester,
    ) async {
      final (:providers, :app) = await _renderList(tester);
      await tester.pumpAndSettle();
      app.fakes.meetings.failure = unauthorized();

      await tester.drag(meetingsListFinder, const Offset(0, -1000));
      await _letItEnd(tester);

      expect(
        providers.read(accessControllerProvider).sessionEndedBy,
        'unauthorized',
      );
      await _routerRemovesTheScreen(tester, providers);
      expect(_listIsInMemory(providers), isFalse);
      await finish(tester, providers);
    });
  });

  group('when the session ends while a meeting is on the screen', () {
    for (final (code, end) in _sessionEndings) {
      testWidgets(
        'sends the user to the screen that fits and empties the cache: $code',
        (tester) async {
          final (:providers, :app) = await _renderDetail(tester);
          await tester.pumpAndSettle();

          await end(app);
          providers.invalidate(meetingQueryProvider(_meeting.id));
          await _letItEnd(tester);

          expect(accessOf(providers), _accessAfter(code));
          expect(providers.read(accessControllerProvider).sessionEndedBy, code);
          await _routerRemovesTheScreen(tester, providers);
          expect(providers.exists(meetingQueryProvider(_meeting.id)), isFalse);
          await finish(tester, providers);
        },
      );
    }
  });

  group('when a meeting that was on the screen is refused or gone', () {
    testWidgets('shows the refusal in place of the meeting, with no retry', (
      tester,
    ) async {
      final (:providers, :app) = await _renderDetail(tester);
      await tester.pumpAndSettle();
      expect(find.text(_meeting.title), findsOneWidget);
      app.fakes.meetings.forbid(_meeting.id);

      providers.invalidate(meetingQueryProvider(_meeting.id));
      await tester.pumpAndSettle();

      expect(
        _within(
          MeetingsTestIds.meetingError,
          find.text(en.coreErrorsForbidden),
        ),
        findsOneWidget,
      );
      expect(
        _within(
          MeetingsTestIds.meetingError,
          byTestId(CoreTestIds.retryButton),
        ),
        findsNothing,
      );
      expect(find.text(_meeting.title), findsNothing);
      expect(byTestId(MeetingsTestIds.meetingDetail), findsNothing);
      await finish(tester, providers);
    });

    testWidgets('shows that it does not exist in place of the meeting', (
      tester,
    ) async {
      final (:providers, :app) = await _renderDetail(tester);
      await tester.pumpAndSettle();
      app.fakes.meetings.removeMeeting(_meeting.id);

      providers.invalidate(meetingQueryProvider(_meeting.id));
      await tester.pumpAndSettle();

      expect(
        _within(
          MeetingsTestIds.meetingNotFound,
          find.text(en.coreErrorsNotFound),
        ),
        findsOneWidget,
      );
      expect(find.text(_meeting.title), findsNothing);
      expect(byTestId(MeetingsTestIds.meetingDetail), findsNothing);
      await finish(tester, providers);
    });

    testWidgets(
      'keeps the meeting, and offers the retry, for a failure that can pass',
      (tester) async {
        final (:providers, :app) = await _renderDetail(tester);
        await tester.pumpAndSettle();
        app.fakes.meetings.failure = unexpected();

        providers.invalidate(meetingQueryProvider(_meeting.id));
        await tester.pumpAndSettle();

        expect(
          _within(CoreTestIds.refreshError, find.text(en.coreErrorsUnexpected)),
          findsOneWidget,
        );
        expect(
          _within(CoreTestIds.refreshError, byTestId(CoreTestIds.retryButton)),
          findsOneWidget,
        );
        expect(byTestId(MeetingsTestIds.meetingDetail), findsOneWidget);
        await finish(tester, providers);
      },
    );
  });

  group('the error of a next page', () {
    for (final (reason, text) in [
      ('the server cannot be reached', en.coreErrorsNetworkUnavailable),
      ('the server fails', en.coreErrorsUnexpected),
    ]) {
      testWidgets('says why, with its own text, when $reason', (tester) async {
        final (:providers, :app) = await _renderList(tester);
        await tester.pumpAndSettle();
        if (text == en.coreErrorsUnexpected) {
          app.fakes.meetings.failure = unexpected();
        } else {
          app.fakes.network.goOffline();
        }

        await reachEnd(tester);

        expect(
          _within(MeetingsTestIds.meetingsLoadMoreError, find.text(text)),
          findsOneWidget,
        );
        expect(
          _within(
            MeetingsTestIds.meetingsLoadMoreError,
            byTestId(CoreTestIds.retryButton),
          ),
          findsOneWidget,
        );
        await finish(tester, providers);
      });
    }
  });

  group('a rejection that is not the failure of a use case', () {
    void boom() => throw Exception('boom');

    testWidgets(
      'shows the list as an unexpected error with a retry, instead of crashing',
      (tester) async {
        useShortWindow(tester);
        final app = TestApp(meetingsPageSize: testPageSize);
        app.fakes.meetings
          ..setMeetings(MeetingPeriod.upcoming, _upcoming)
          ..onRequest = boom;
        final providers = await pumpPagedScreen(
          tester,
          const MeetingsListScreen(),
          app: app,
        );
        await tester.pumpAndSettle();

        expect(
          _within(
            MeetingsTestIds.meetingsError,
            find.text(en.coreErrorsUnexpected),
          ),
          findsOneWidget,
        );
        expect(
          _within(
            MeetingsTestIds.meetingsError,
            byTestId(CoreTestIds.retryButton),
          ),
          findsOneWidget,
        );
        await finish(tester, providers);
      },
    );

    testWidgets(
      'shows the meeting as an unexpected error with a retry, instead of '
      'crashing',
      (tester) async {
        final app = TestApp(meetingsPageSize: testPageSize);
        app.fakes.meetings
          ..addMeeting(_meeting)
          ..onRequest = boom;
        final providers = await pumpScreen(
          tester,
          MeetingDetailScreen(meetingId: _meeting.id),
          app: app,
        );
        await tester.pumpAndSettle();

        expect(
          _within(
            MeetingsTestIds.meetingError,
            find.text(en.coreErrorsUnexpected),
          ),
          findsOneWidget,
        );
        expect(
          _within(
            MeetingsTestIds.meetingError,
            byTestId(CoreTestIds.retryButton),
          ),
          findsOneWidget,
        );
        await finish(tester, providers);
      },
    );

    testWidgets(
      'shows an error next to the rows when the refresh is the one that '
      'rejects',
      (tester) async {
        final (:providers, :app) = await _renderList(tester);
        await tester.pumpAndSettle();
        app.fakes.meetings.onRequest = boom;

        await pullToRefresh(tester);

        expect(
          _within(CoreTestIds.refreshError, find.text(en.coreErrorsUnexpected)),
          findsOneWidget,
        );
        expect(shownIds(tester), ['u1', 'u2', 'u3']);
        await finish(tester, providers);
      },
    );
  });

  group('a second user on the same device', () {
    final second = aSession(user: aUser(id: aUserId('user-2')));
    final otherMeetings = meetingsOf('b', 2, MeetingPeriod.upcoming);

    /// What a sign-out and a sign-in do to the interface: the screens are left
    /// and the access moves on, which ends the life of what the queries held.
    void signOutAndIn(ProviderContainer providers) {
      providers.read(accessControllerProvider.notifier)
        ..signedOut()
        ..signedIn();
    }

    testWidgets(
      'never sees the rows of the first user, not even while their own '
      'request is in flight',
      (tester) async {
        final (:providers, :app) = await _renderList(tester);
        await tester.pumpAndSettle();

        await tester.pumpWidget(testHost(providers, const SizedBox.shrink()));
        signOutAndIn(providers);
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 10));
        app.fakes.auth.session = second;
        app.fakes.meetings.setMeetings(MeetingPeriod.upcoming, otherMeetings);
        final gate = Completer<void>();
        app.fakes.meetings.onRequest = () => gate.future;
        await tester.pumpWidget(
          testHost(providers, const MeetingsListScreen()),
        );
        await tester.pump();

        expect(byTestId(MeetingsTestIds.meetingsLoading), findsOneWidget);
        expect(shownIds(tester), isEmpty);

        gate.complete();
        await tester.pumpAndSettle();
        expect(shownIds(tester), ['b1', 'b2']);
        await finish(tester, providers);
      },
    );

    testWidgets(
      'would see them, until their own answer comes, if the cache were not '
      'emptied: that is what the sign-out is for',
      (tester) async {
        final (:providers, :app) = await _renderList(tester);
        await tester.pumpAndSettle();

        await tester.pumpWidget(testHost(providers, const SizedBox.shrink()));
        app.fakes.auth.session = second;
        app.fakes.meetings.setMeetings(MeetingPeriod.upcoming, otherMeetings);
        final gate = Completer<void>();
        app.fakes.meetings.onRequest = () => gate.future;
        await tester.pumpWidget(
          testHost(providers, const MeetingsListScreen()),
        );
        await tester.pump();

        expect(shownIds(tester), ['u1', 'u2', 'u3']);
        gate.complete();
        await tester.pumpAndSettle();
        await finish(tester, providers);
      },
    );

    testWidgets(
      'is told, by the use case, when the user changed under a request that '
      'was in flight',
      (tester) async {
        useShortWindow(tester);
        final app = TestApp(meetingsPageSize: testPageSize);
        app.fakes.meetings
          ..setMeetings(MeetingPeriod.upcoming, _upcoming)
          ..onRequest = () {
            app.fakes.auth.session = second;
          };
        final providers = await pumpPagedScreen(
          tester,
          const MeetingsListScreen(),
          app: app,
        );
        await _letItEnd(tester);

        expect(
          providers.read(accessControllerProvider).sessionEndedBy,
          'sessionChanged',
        );
        await finish(tester, providers);
      },
    );
  });

  testWidgets(
    'does not end the session for a meeting that is refused: only that '
    'meeting is lost',
    (tester) async {
      final (:providers, :app) = await _renderDetail(tester);
      await tester.pumpAndSettle();
      app.fakes.meetings.forbid(_meeting.id);

      providers.invalidate(meetingQueryProvider(_meeting.id));
      await tester.pumpAndSettle();

      expect(byTestId(MeetingsTestIds.meetingError), findsOneWidget);
      expect(accessOf(providers), Access.unlocked);
      expect(providers.read(accessControllerProvider).sessionEndedBy, isNull);
      await finish(tester, providers);
    },
  );
}
