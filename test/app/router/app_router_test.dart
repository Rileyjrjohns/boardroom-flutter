import 'dart:async';

import 'package:boardroom/app/router/app_router.dart';
import 'package:boardroom/core/presentation/navigation/routes.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/features/documents/presentation/test_ids.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/builders/builders.dart';
import '../../support/presentation/fake_demo_network.dart';
import '../../support/presentation/test_app.dart';

// The navigation map of docs/spec/screens.md: which route exists for which
// access, the guards, and the deep links.

String? _redirect(Access access, String location, {bool demo = false}) =>
    redirectOf(access: access, location: Uri.parse(location), demoRoutes: demo);

Finder _inHeader(String title) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(title));

/// An app whose server holds the meeting `m1`, so that its screen is the
/// meeting and not the "not found" message.
TestApp _appWithMeeting() => TestApp()
  ..fakes.meetings.addMeeting(
    aMeeting(summary: aMeetingSummary(id: aMeetingId('m1'))),
  );

/// The queries keep timers: the tree is emptied and the container disposed
/// before the test ends.
Future<void> _endApp(WidgetTester tester, ProviderContainer providers) async {
  await tester.pumpWidget(const SizedBox.shrink());
  providers.dispose();
}

void main() {
  group('redirectOf', () {
    test('decides nothing while the app starts', () {
      expect(_redirect(Access.starting, '/sign-in'), isNull);
      expect(_redirect(Access.starting, '/meetings/m1'), isNull);
    });

    test('a signed-out user only has the sign-in route', () {
      expect(_redirect(Access.signedOut, '/sign-in'), isNull);
      for (final path in [
        '/',
        '/lock',
        '/pending-votes',
        '/meetings/m1',
        '/documents/d1',
        '/nowhere',
      ]) {
        expect(_redirect(Access.signedOut, path), '/sign-in', reason: path);
      }
    });

    test('a locked app only has the lock route', () {
      expect(_redirect(Access.locked, '/lock'), isNull);
      for (final path in ['/', '/sign-in', '/meetings/m1', '/pending-votes']) {
        expect(_redirect(Access.locked, path), '/lock', reason: path);
      }
    });

    test('an open app has the four routes of the open app', () {
      for (final path in [
        '/',
        '/pending-votes',
        '/meetings/m1',
        '/documents/d1',
      ]) {
        expect(_redirect(Access.unlocked, path), isNull, reason: path);
      }
      for (final path in [
        '/sign-in',
        '/lock',
        '/meetings',
        '/meetings/m1/extra',
        '/documents/',
        '/nowhere',
      ]) {
        expect(_redirect(Access.unlocked, path), '/', reason: path);
      }
    });

    test('no deep link reaches a protected route, and the link is not '
        'remembered', () {
      expect(_redirect(Access.signedOut, '/meetings/m1'), '/sign-in');
      expect(_redirect(Access.locked, '/documents/d1'), '/lock');
    });

    test('drops a link that is too long or badly encoded', () {
      final long = '/meetings/${'a' * maxLinkLength}';

      expect(_redirect(Access.unlocked, long), '/');
      expect(_redirect(Access.unlocked, '/meetings/%E0%A4%A'), '/');
      expect(_redirect(Access.signedOut, '/meetings/%'), '/sign-in');
    });

    test('lets the demo screen through in the dev configuration only', () {
      const demo = '/screen-protection-demo';

      expect(_redirect(Access.signedOut, demo, demo: true), isNull);
      expect(_redirect(Access.unlocked, demo, demo: true), isNull);
      expect(_redirect(Access.unlocked, demo), '/');
    });

    test('the home of each access is the one screen that exists', () {
      expect(homeOf(Access.signedOut), '/sign-in');
      expect(homeOf(Access.locked), '/lock');
      expect(homeOf(Access.unlocked), '/');
      expect(homeOf(Access.starting), '/');
    });
  });

  group('the router', () {
    Future<(ProviderContainer, GoRouter)> pump(
      WidgetTester tester, {
      Access access = Access.signedOut,
      TestApp? app,
    }) async {
      final providers = (app ?? TestApp()).providers(access: access);
      final router = providers.read(appRouterProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: providers,
          // A widget that watches the access, like the session controller of
          // the app: it is what keeps the providers refreshing with the frames.
          child: Consumer(
            builder: (context, ref, _) {
              ref.watch(accessProvider);
              return MaterialApp.router(
                routerConfig: router,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (providers, router);
    }

    testWidgets('shows the screen of each access, with its title', (
      tester,
    ) async {
      final (providers, router) = await pump(tester);
      final en = l10nOf();
      expect(byTestId(AuthTestIds.signInScreen), findsOneWidget);
      expect(_inHeader(en.coreNavigationSignIn), findsOneWidget);

      providers.read(accessControllerProvider.notifier).signedIn();
      await tester.pumpAndSettle();
      expect(byTestId(MeetingsTestIds.meetingsList), findsOneWidget);
      expect(_inHeader(en.coreNavigationMeetings), findsOneWidget);

      providers
          .read(accessControllerProvider.notifier)
          .locked(providers.read(accessControllerProvider).epoch);
      await tester.pumpAndSettle();
      expect(byTestId(AuthTestIds.lockScreen), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/lock');
    });

    testWidgets('mounts the four screens of the open app by their paths', (
      tester,
    ) async {
      final (providers, router) = await pump(
        tester,
        access: Access.unlocked,
        app: _appWithMeeting(),
      );

      router.go('/meetings/m1');
      await tester.pumpAndSettle();
      expect(byTestId(MeetingsTestIds.meetingDetail), findsOneWidget);

      router.go('/documents/d1');
      await tester.pumpAndSettle();
      expect(byTestId(DocumentsTestIds.documentScreen), findsOneWidget);

      router.go(AppRoutes.pendingVotes.path);
      await tester.pumpAndSettle();
      expect(byTestId(VotesTestIds.pendingVotesScreen), findsOneWidget);
      await _endApp(tester, providers);
    });

    testWidgets('removes the screens of the open app, history included, '
        'when the session ends, and starts anew when the user is back', (
      tester,
    ) async {
      final (providers, router) = await pump(
        tester,
        access: Access.unlocked,
        app: _appWithMeeting(),
      );
      unawaited(router.push('/meetings/m1'));
      await tester.pumpAndSettle();
      expect(byTestId(MeetingsTestIds.meetingDetail), findsOneWidget);

      providers
          .read(accessControllerProvider.notifier)
          .endSession('sessionExpired', 0);
      await tester.pumpAndSettle();

      expect(byTestId(AuthTestIds.signInScreen), findsOneWidget);
      expect(byTestId(MeetingsTestIds.meetingDetail), findsNothing);
      expect(router.canPop(), isFalse);

      providers.read(accessControllerProvider.notifier).signedIn();
      await tester.pumpAndSettle();
      expect(byTestId(MeetingsTestIds.meetingsList), findsOneWidget);
      expect(router.canPop(), isFalse);
      await _endApp(tester, providers);
    });

    testWidgets('does not open a protected link while signed out', (
      tester,
    ) async {
      final (_, router) = await pump(tester);

      router.go('/meetings/m1');
      await tester.pumpAndSettle();

      expect(byTestId(AuthTestIds.signInScreen), findsOneWidget);
      expect(byTestId(MeetingsTestIds.meetingDetail), findsNothing);
    });

    testWidgets('reaches the demo screen in the dev configuration', (
      tester,
    ) async {
      final app = TestApp(demoControls: aDemoControls());
      final (_, router) = await pump(tester, app: app);

      router.go(AppRoutes.screenProtectionDemo.path);
      await tester.pumpAndSettle();

      expect(
        find.text(l10nOf().documentsScreenProtectionDemoSwitch),
        findsOneWidget,
      );
    });
  });
}
