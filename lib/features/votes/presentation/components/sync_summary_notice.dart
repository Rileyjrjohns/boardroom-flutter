import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/components/status_banner.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/votes/presentation/state/sync_summary.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the last synchronisations of the votes did, in the banner of the
/// screens of the open app: how many votes were sent and how many were refused,
/// added up until the user dismisses it. Nothing at all while there is nothing
/// to tell.
class SyncSummaryNotice extends ConsumerWidget {
  /// Creates the notice.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summary = ref.watch(syncSummaryStateProvider);
    if (summary == null) {
      return const SizedBox.shrink();
    }
    const text = TextStyle(
      fontSize: AppFontSizes.caption,
      color: AppColors.warningText,
    );
    return Column(
      key: const Key(VotesTestIds.syncSummary),
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.sm,
      children: [
        if (summary.synced != 0)
          LiveText(message: l10n.votesBannerSent(summary.synced), style: text),
        if (summary.rejected != 0)
          LiveText(
            message: l10n.coreBannerRejected(summary.rejected),
            style: text,
          ),
        AppButton(
          key: const Key(VotesTestIds.syncSummaryDismiss),
          title: l10n.coreBannerDismiss,
          variant: AppButtonVariant.secondary,
          onPressed: () =>
              ref.read(syncSummaryStateProvider.notifier).dismiss(),
        ),
      ],
    );
  }
}

/// What the votes add to the banner of the screens: the slot of the shared
/// banner (`StatusBanner`). The banner shows nothing of it while there is no
/// summary.
final BannerNotices syncSummaryNotices = BannerNotices(
  hasNotices: syncSummaryStateProvider.select((summary) => summary != null),
  builder: (context) => const SyncSummaryNotice(),
);
