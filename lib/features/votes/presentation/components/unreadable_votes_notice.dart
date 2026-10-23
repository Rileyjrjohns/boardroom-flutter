import 'dart:async';

import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/app_dialog.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/votes/presentation/error_messages.dart';
import 'package:boardroom/features/votes/presentation/state/vote_actions.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tells the user that some of their saved votes can no longer be read, and
/// offers to delete them. Such an entry is kept, not sent and not shown,
/// because it may be the only trace of a vote: the notice says so, says how
/// many there are, and leaves it to the user to check on the meeting that their
/// vote was recorded. Deleting is irreversible, so it asks for a confirmation
/// that repeats the count; the outbox is read again afterwards, and the notice
/// goes when nothing is left.
class UnreadableVotesNotice extends ConsumerWidget {
  /// Creates the notice for [count] unreadable votes (one or more).
  const new({required this.count, super.key});

  /// How many saved votes of the user can no longer be read.
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Keeps the state of the discard while the confirmation is up.
    ref.listen(discardUnreadableVotesActionProvider, (_, _) {});
    return Container(
      key: const Key(VotesTestIds.unreadableVotes),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      color: AppColors.warningBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Text(l10n.votesPendingVotesUnreadable(count), style: _text),
          AppButton(
            key: const Key(VotesTestIds.unreadableVotesDiscard),
            title: l10n.votesPendingVotesDiscard,
            variant: AppButtonVariant.secondary,
            hint: l10n.votesPendingVotesDiscardHint,
            onPressed: () {
              ref.read(discardUnreadableVotesActionProvider.notifier).reset();
              unawaited(
                showAppDialog<void>(
                  context,
                  builder: (_) => _DiscardDialog(count: count),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DiscardDialog extends ConsumerWidget {
  const new({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final action = ref.watch(discardUnreadableVotesActionProvider);
    final notifier = ref.read(discardUnreadableVotesActionProvider.notifier);
    final failure = action.failure;

    void dismiss() {
      if (action.isPending) {
        return;
      }
      notifier.reset();
      Navigator.of(context).pop();
    }

    Future<void> confirm() async {
      final navigator = Navigator.of(context);
      await notifier.run();
      // A discard that worked closes the confirmation (the notice goes with the
      // unreadable votes); a failure is told in the dialog.
      if (navigator.mounted &&
          ref.read(discardUnreadableVotesActionProvider).failure == null) {
        navigator.pop();
      }
    }

    return AppDialog(
      key: const Key(VotesTestIds.unreadableVotesDialog),
      title: l10n.votesPendingVotesDiscardTitle,
      onDismiss: action.isPending ? null : dismiss,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.sm,
        children: [
          Text(l10n.votesPendingVotesDiscardMessage(count), style: _text),
          if (failure != null)
            KeyedSubtree(
              key: const Key(VotesTestIds.unreadableVotesError),
              child: LiveText(
                message: discardErrorMessage(l10n, failure.code),
                style: const TextStyle(
                  fontSize: AppFontSizes.body,
                  color: AppColors.danger,
                ),
              ),
            ),
        ],
      ),
      actions: [
        AppButton(
          key: const Key(VotesTestIds.unreadableVotesCancel),
          title: l10n.coreCommonCancel,
          variant: AppButtonVariant.secondary,
          onPressed: action.isPending ? null : dismiss,
        ),
        AppButton(
          key: const Key(VotesTestIds.unreadableVotesConfirm),
          title: action.isPending
              ? l10n.votesPendingVotesDiscarding
              : l10n.votesPendingVotesDiscard,
          variant: AppButtonVariant.danger,
          busy: action.isPending,
          onPressed: () => unawaited(confirm()),
        ),
      ],
    );
  }
}

const TextStyle _text = TextStyle(
  fontSize: AppFontSizes.body,
  color: AppColors.warningText,
);
