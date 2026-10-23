import 'package:boardroom/app/shell/header_actions.dart';
import 'package:boardroom/core/presentation/theme/app_theme.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/features/votes/presentation/state/pending_votes.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meta/meta.dart' show isTest;

import '../../support/builders/builders.dart';
import '../../support/presentation/test_app.dart';

// The actions of the header of the meetings list, ported from
// HeaderActions.test.tsx of the React Native app.

const Key _pendingVotesRoute = Key('pending-votes-route');

ProviderContainer? _live;

/// A widget test that ends the app: the queries keep timers, so the tree is
/// emptied and the container disposed before the test ends.
@isTest
void _test(String description, Future<void> Function(WidgetTester) body) =>
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      _live?.dispose();
      _live = null;
    });

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  TestApp? app,
  Locale locale = const Locale('en'),
}) async {
  final providers = _live = (app ?? TestApp()).providers();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: HeaderActions()),
      ),
      GoRoute(
        path: '/pending-votes',
        builder: (_, _) => const SizedBox(key: _pendingVotesRoute),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: providers,
      child: MaterialApp.router(
        locale: locale,
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return providers;
}

void main() {
  final en = l10nOf();

  group('HeaderActions', () {
    _test('offers the pending votes and signing out, each at least as '
        'big as a touch target', (tester) async {
      await _pump(tester);

      final pending = tester.getSize(byTestId(VotesTestIds.pendingVotesButton));
      final signOut = tester.getSize(byTestId(AuthTestIds.signOutButton));

      expect(find.bySemanticsLabel(en.votesPendingVotesOpen), findsOneWidget);
      expect(find.text(en.authSignOutAction), findsOneWidget);
      expect(pending.height, greaterThanOrEqualTo(44));
      expect(pending.width, greaterThanOrEqualTo(44));
      expect(signOut.height, greaterThanOrEqualTo(44));
      expect(signOut.width, greaterThanOrEqualTo(44));
    });

    _test('shows no count when no vote is waiting', (tester) async {
      await _pump(tester);

      expect(byTestId(VotesTestIds.pendingVotesBadge), findsNothing);
    });

    _test('counts the votes that wait and the ones that were rejected, '
        'in the badge and in the name of the button', (tester) async {
      final app = TestApp();
      app.fakes.outbox.seed([
        aPendingVote(aVote(resolutionId: aResolutionId('r1'))),
        aPendingVote(aVote(resolutionId: aResolutionId('r2'))),
        aRejectedVote(aVote(resolutionId: aResolutionId('r3'))),
      ]);
      await _pump(tester, app: app);

      expect(
        find.descendant(
          of: byTestId(VotesTestIds.pendingVotesBadge),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(en.votesPendingVotesOpenWithCount('3')),
        findsOneWidget,
      );
    });

    _test('updates the count when the outbox changes', (tester) async {
      final app = TestApp();
      final providers = await _pump(tester, app: app);
      app.fakes.outbox.seed([
        aPendingVote(aVote(resolutionId: aResolutionId('r1'))),
      ]);

      providers.invalidate(pendingVotesProvider);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: byTestId(VotesTestIds.pendingVotesBadge),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    _test('opens the pending votes', (tester) async {
      await _pump(tester);

      await tester.tap(byTestId(VotesTestIds.pendingVotesButton));
      await tester.pumpAndSettle();

      expect(find.byKey(_pendingVotesRoute), findsOneWidget);
    });

    _test('asks for a confirmation before signing out, which says how '
        'many votes are kept', (tester) async {
      final app = TestApp();
      app.fakes.outbox.seed([
        aPendingVote(aVote(resolutionId: aResolutionId('r1'))),
      ]);
      final providers = await _pump(tester, app: app);

      await tester.tap(byTestId(AuthTestIds.signOutButton));
      await tester.pumpAndSettle();

      expect(find.text(en.authSignOutTitle), findsOneWidget);
      expect(
        find.descendant(
          of: byTestId(AuthTestIds.signOutPending),
          matching: find.text(en.authSignOutPending(1)),
        ),
        findsOneWidget,
      );
      expect(providers.read(accessProvider), Access.unlocked);
    });

    _test('signs out only when the user confirms, and closes the '
        'confirmation when they cancel', (tester) async {
      final app = TestApp();
      final providers = await _pump(tester, app: app);

      await tester.tap(byTestId(AuthTestIds.signOutButton));
      await tester.pumpAndSettle();
      await tester.tap(byTestId(AuthTestIds.signOutCancel));
      await tester.pumpAndSettle();
      expect(byTestId(AuthTestIds.signOutDialog), findsNothing);
      expect(app.fakes.auth.signOutCalls, 0);

      await tester.tap(byTestId(AuthTestIds.signOutButton));
      await tester.pumpAndSettle();
      await tester.tap(byTestId(AuthTestIds.signOutConfirm));
      await tester.pumpAndSettle();

      expect(app.fakes.auth.signOutCalls, 1);
      expect(providers.read(accessProvider), Access.signedOut);
    });

    for (final language in ['en', 'fr']) {
      _test('is written in $language', (tester) async {
        final locale = Locale(language);
        await _pump(tester, locale: locale);
        final texts = l10nOf(locale);

        expect(find.text(texts.votesPendingVotesOpen), findsOneWidget);
        expect(find.text(texts.authSignOutAction), findsOneWidget);
      });
    }
  });
}
