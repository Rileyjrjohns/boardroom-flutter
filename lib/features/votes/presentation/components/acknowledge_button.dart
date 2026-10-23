import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/votes/presentation/error_messages.dart';
import 'package:boardroom/features/votes/presentation/state/vote_actions.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "I have seen it": deletes the rejected vote on a resolution from the outbox.
/// A rejected vote blocks a new one until it is acknowledged, so it is offered
/// wherever the rejection is told (the resolution, the list of pending votes).
/// If the vote cannot be removed the reason is told next to the button.
class AcknowledgeButton extends ConsumerWidget {
  /// Creates the button for the rejected vote on [resolutionId].
  const new({required this.resolutionId, super.key});

  /// The resolution whose rejected vote is acknowledged.
  final ResolutionId resolutionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final action = ref.watch(
      acknowledgeRejectedVoteActionProvider(resolutionId),
    );
    final failure = action.failure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        AppButton(
          key: Key(acknowledgeTestId(resolutionId)),
          title: l10n.votesVotingAcknowledge,
          variant: AppButtonVariant.secondary,
          busy: action.isPending,
          hint: l10n.votesVotingAcknowledgeHint,
          onPressed: () => ref
              .read(
                acknowledgeRejectedVoteActionProvider(resolutionId).notifier,
              )
              .run(),
        ),
        if (failure != null)
          LiveText(
            message: acknowledgeErrorMessage(l10n, failure.code),
            style: const TextStyle(
              fontSize: AppFontSizes.caption,
              color: AppColors.danger,
            ),
          ),
      ],
    );
  }
}
