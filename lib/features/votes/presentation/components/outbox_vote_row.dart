import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/presentation/components/acknowledge_button.dart';
import 'package:boardroom/features/votes/presentation/error_messages.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A vote of the outbox: the choice and when it was cast, and what became of
/// it. A vote that waits says so by being in the first list of its screen; a
/// vote that was rejected tells why and can be acknowledged. The outbox holds
/// the ids of the meeting and the resolution and not their titles, so the row
/// leads to the meeting, where the resolution is.
class OutboxVoteRow extends StatelessWidget {
  /// Creates the row of [entry]; [onOpenMeeting] opens the meeting the vote is
  /// about (the resolution it was cast on is there).
  const new({required this.entry, required this.onOpenMeeting, super.key});

  /// The vote.
  final OutboxVote entry;

  /// Opens the meeting.
  final void Function(MeetingId id) onOpenMeeting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = Formatters.of(context);
    final vote = entry.vote;
    final rejected = entry;
    return Container(
      key: Key(
        rejected is RejectedVote
            ? rejectedVoteTestId(vote.resolutionId)
            : pendingVoteTestId(vote.resolutionId),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          Text(
            l10n.meetingsMeetingResolutionYourVote(
              voteChoiceLabel(l10n, vote.choice),
            ),
            style: const TextStyle(
              fontSize: AppFontSizes.body,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            l10n.votesPendingVotesCastAt(formatters.dateTime(vote.castAt)),
            style: _detail,
          ),
          if (rejected is RejectedVote) ...[
            LiveText(
              message: rejectionReasonMessage(l10n, rejected.reason),
              style: const TextStyle(
                fontSize: AppFontSizes.body,
                color: AppColors.danger,
              ),
            ),
            Text(
              l10n.votesPendingVotesRejectedAt(
                formatters.dateTime(rejected.rejectedAt),
              ),
              style: _detail,
            ),
            AcknowledgeButton(resolutionId: vote.resolutionId),
          ],
          AppButton(
            key: Key(openVoteMeetingTestId(vote.resolutionId)),
            title: l10n.votesPendingVotesOpenMeeting,
            variant: AppButtonVariant.secondary,
            onPressed: () => onOpenMeeting(vote.meetingId),
          ),
        ],
      ),
    );
  }
}

const TextStyle _detail = TextStyle(
  fontSize: AppFontSizes.caption,
  color: AppColors.textSecondary,
);
