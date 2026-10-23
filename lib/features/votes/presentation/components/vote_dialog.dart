import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/app_dialog.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/errors/error_catalog.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/presentation/error_messages.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether pressing "confirm" again can work after [failure]: the codes a query
/// may be tried again for, and the ones only the user can retry (see
/// `retryableByTheUser`).
bool canConfirmAgain(AppError failure, ErrorCatalog catalog) =>
    catalog.isRetryableCode(failure.code) ||
    retryableByTheUser.contains(failure.code);

/// The confirmation step of a vote. It states, before anything is cast, what
/// the user is about to do and that it is final, and it is the only place a
/// vote is cast from: confirming asks for the biometric proof (`CastVote`), and
/// every outcome that is not a success is told here, in the dialog, with the
/// choice still under review so that the user can try again when trying again
/// can help. Pending, the confirm button is busy and cannot be pressed again,
/// so one tap casts one vote.
///
/// It is the body of the dialog: `ResolutionVoting` opens it with
/// `showAppDialog` and closes it.
class VoteDialog extends ConsumerWidget {
  /// Creates the dialog for the review of [choice].
  const new({
    required this.choice,
    required this.resolutionTitle,
    required this.offline,
    required this.pending,
    required this.failure,
    required this.onConfirm,
    required this.onDismiss,
    super.key,
  });

  /// The choice under review.
  final VoteChoice choice;

  /// The title of the resolution being voted on.
  final String resolutionTitle;

  /// Whether the device says it is offline: the vote will be saved and sent
  /// later.
  final bool offline;

  /// The vote is being cast: the biometric prompt is up, or the server is
  /// answering.
  final bool pending;

  /// Why the last attempt failed.
  final AppError? failure;

  /// Confirms the vote.
  final VoidCallback onConfirm;

  /// Closes the dialog without casting.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(errorCatalogProvider);
    final error = failure;
    final isFinal = error != null && !canConfirmAgain(error, catalog);
    const text = TextStyle(
      fontSize: AppFontSizes.body,
      color: AppColors.textPrimary,
    );

    return AppDialog(
      key: const Key(VotesTestIds.voteDialog),
      title: l10n.votesVotingConfirmTitle,
      // The back gesture does nothing while the vote is being cast.
      onDismiss: pending ? null : onDismiss,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.sm,
        children: [
          Text(
            resolutionTitle,
            style: const TextStyle(
              fontSize: AppFontSizes.body,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            l10n.votesVotingConfirmChoice(voteChoiceLabel(l10n, choice)),
            key: const Key(VotesTestIds.voteDialogChoice),
            style: const TextStyle(
              fontSize: AppFontSizes.subtitle,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            l10n.votesVotingConfirmFinal,
            key: const Key(VotesTestIds.voteDialogFinal),
            style: text,
          ),
          Text(l10n.votesVotingConfirmBiometric, style: text),
          if (offline)
            Text(
              l10n.votesVotingConfirmOffline,
              key: const Key(VotesTestIds.voteDialogOffline),
              style: text,
            ),
          if (error != null)
            KeyedSubtree(
              key: const Key(VotesTestIds.voteDialogError),
              child: LiveText(
                message: castVoteErrorMessage(l10n, error),
                style: const TextStyle(
                  fontSize: AppFontSizes.body,
                  color: AppColors.danger,
                ),
              ),
            ),
        ],
      ),
      actions: isFinal
          ? [
              AppButton(
                key: const Key(VotesTestIds.voteClose),
                title: l10n.coreCommonClose,
                variant: AppButtonVariant.secondary,
                onPressed: onDismiss,
              ),
            ]
          : [
              AppButton(
                key: const Key(VotesTestIds.voteCancel),
                title: l10n.coreCommonCancel,
                variant: AppButtonVariant.secondary,
                onPressed: pending ? null : onDismiss,
              ),
              AppButton(
                key: const Key(VotesTestIds.voteConfirm),
                title: pending
                    ? l10n.votesVotingConfirming
                    : l10n.votesVotingConfirm,
                busy: pending,
                onPressed: onConfirm,
              ),
            ],
    );
  }
}
