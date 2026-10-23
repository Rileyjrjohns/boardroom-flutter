import 'package:boardroom/core/presentation/components/demo_controls_view.dart';
import 'package:boardroom/core/presentation/components/error_views.dart';
import 'package:boardroom/core/presentation/components/loading_state.dart';
import 'package:boardroom/core/presentation/components/message.dart';
import 'package:boardroom/core/presentation/components/status_banner.dart';
import 'package:boardroom/core/presentation/navigation/navigate.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/query/query_failure.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/presentation/components/outbox_vote_row.dart';
import 'package:boardroom/features/votes/presentation/components/unreadable_votes_notice.dart';
import 'package:boardroom/features/votes/presentation/state/pending_votes.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The pending and rejected votes (docs/spec/screens.md "Pending votes").
///
/// The votes of the user that are not settled: the ones waiting to be sent
/// (cast without a connection, or when the server failed) and the ones that
/// were rejected, with their reason, until the user acknowledges them. They
/// come from the outbox through `ListPendingVotes`. The votes are sent by the
/// synchronisation, never from here: the screen shows what is waiting and what
/// became of it, and a pull asks the outbox again.
class PendingVotesScreen extends ConsumerWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(errorCatalogProvider);
    final votes = ref.watch(pendingVotesProvider);
    final content = votes.value;
    final code = votes.hasError ? errorCodeOf(votes.error, catalog) : null;

    void retry() => ref.invalidate(pendingVotesProvider);

    if (content == null && code == null) {
      return KeyedSubtree(
        key: const Key(VotesTestIds.pendingVotesLoading),
        child: LoadingState(label: l10n.votesPendingVotesLoading),
      );
    }
    // An error that asking again cannot fix is final for the screen, and
    // replaces what was loaded.
    if (code != null && (content == null || !catalog.isRetryableCode(code))) {
      return KeyedSubtree(
        key: const Key(VotesTestIds.pendingVotesError),
        child: ErrorState(code: code, onRetry: retry),
      );
    }

    final pending = content!.pending;
    final rejected = content.rejected;
    final unreadable = content.unreadable;

    Widget row(OutboxVote entry) => OutboxVoteRow(
      key: ValueKey(entry.vote.idempotencyKey),
      entry: entry,
      onOpenMeeting: (id) => openMeeting(context, id),
    );

    return RefreshIndicator(
      semanticsLabel: l10n.coreStatesRefreshing,
      onRefresh: () async {
        ref.invalidate(pendingVotesProvider);
        try {
          await ref.read(pendingVotesProvider.future);
        } on Object {
          // Told by the inline error below.
        }
      },
      child: SingleChildScrollView(
        key: const Key(VotesTestIds.pendingVotesScreen),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StatusBanner(),
            const DemoOfflineSwitch(),
            if (votes.hasError && code != null)
              InlineError(
                key: const Key(CoreTestIds.refreshError),
                code: code,
                onRetry: retry,
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                l10n.votesPendingVotesExplanation,
                style: const TextStyle(
                  fontSize: AppFontSizes.body,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (unreadable != 0) UnreadableVotesNotice(count: unreadable),
            if (pending.isEmpty && rejected.isEmpty)
              KeyedSubtree(
                key: const Key(VotesTestIds.pendingVotesEmpty),
                child: Message(
                  message: l10n.votesPendingVotesEmpty,
                  centered: true,
                ),
              ),
            if (pending.isNotEmpty)
              _Section(
                key: const Key(VotesTestIds.pendingVotesWaiting),
                title: l10n.votesPendingVotesWaiting,
                children: [for (final entry in pending) row(entry)],
              ),
            if (rejected.isNotEmpty)
              _Section(
                key: const Key(VotesTestIds.pendingVotesRejected),
                title: l10n.votesPendingVotesRejected,
                children: [for (final entry in rejected) row(entry)],
              ),
          ],
        ),
      ),
    );
  }
}

/// A titled list of rows.
class _Section extends StatelessWidget {
  const new({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: const TextStyle(
              fontSize: AppFontSizes.subtitle,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        ...children,
      ],
    ),
  );
}
