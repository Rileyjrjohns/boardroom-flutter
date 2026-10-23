import 'package:boardroom/core/presentation/components/status_banner.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/votes/presentation/components/sync_summary_notice.dart';
import 'package:boardroom/features/votes/presentation/state/sync_summary.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/presentation/test_app.dart';

// What the votes add to the banner of the screens (the slot of the shared
// banner): the sum of the synchronisations, until the user has read it. The
// banner with every other fact is tested with the core.

Future<void> _end(WidgetTester tester, ProviderContainer providers) async {
  await tester.pumpWidget(const SizedBox.shrink());
  providers.dispose();
}

void _show(ProviderContainer providers, int synced, int rejected) {
  providers
      .read(syncSummaryStateProvider.notifier)
      .show(
        SyncSummary(synced: synced, rejected: rejected),
        providers.read(accessControllerProvider).epoch,
      );
}

void main() {
  final en = l10nOf();

  group('syncSummaryNotices', () {
    test('has something to tell once a synchronisation sent or '
        'refused a vote, until it is dismissed', () {
      final providers = TestApp().providers();
      final hasNotices = providers.read(
        providers.read(bannerNoticesProvider).hasNotices,
      );
      expect(hasNotices, isFalse);

      _show(providers, 1, 0);
      expect(
        providers.read(providers.read(bannerNoticesProvider).hasNotices),
        isTrue,
      );

      providers.read(syncSummaryStateProvider.notifier).dismiss();
      expect(
        providers.read(providers.read(bannerNoticesProvider).hasNotices),
        isFalse,
      );
    });

    testWidgets('is the summary of the banner: the counts, and '
        'a button that dismisses it', (tester) async {
      final providers = await pumpScreen(tester, const StatusBanner());
      _show(providers, 2, 1);
      await tester.pump();

      expect(byTestId(VotesTestIds.syncSummary), findsOneWidget);
      expect(find.text(en.votesBannerSent(2)), findsOneWidget);
      expect(find.text(en.coreBannerRejected(1)), findsOneWidget);

      await tester.tap(byTestId(VotesTestIds.syncSummaryDismiss));
      await tester.pump();

      expect(providers.read(syncSummaryStateProvider), isNull);
      expect(byTestId(VotesTestIds.syncSummary), findsNothing);
      await _end(tester, providers);
    });

    testWidgets('tells only the votes that were sent when none was refused', (
      tester,
    ) async {
      final providers = await pumpScreen(tester, const StatusBanner());
      _show(providers, 1, 0);
      await tester.pump();

      expect(find.text(en.votesBannerSent(1)), findsOneWidget);
      expect(find.text(en.coreBannerRejected(1)), findsNothing);
      await _end(tester, providers);
    });

    testWidgets('renders nothing of its own while there is nothing to tell', (
      tester,
    ) async {
      final providers = await pumpScreen(tester, const SyncSummaryNotice());

      expect(byTestId(VotesTestIds.syncSummary), findsNothing);
      await _end(tester, providers);
    });
  });
}
