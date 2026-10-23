import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/presentation/components/badge.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/policies/voting_state.dart';
import 'package:boardroom/features/meetings/presentation/components/resolution_vote_line.dart';
import 'package:boardroom/features/meetings/presentation/messages.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The resolution of an agenda item: its title and text, where voting stands
/// (open, closed, or its window over, told by the same rule as the eligibility
/// to vote), the deadline or the date it closed on, and the vote of the user:
/// the one the server recorded, or none. When a feature plugs actions into the
/// slot ([actions]), they come in the place of that line, and offer what the
/// user can do about the resolution.
class ResolutionView extends StatelessWidget {
  /// Creates the card of [resolution], judged at [now].
  const new({
    required this.resolution,
    required this.now,
    this.actions,
    super.key,
  });

  /// The resolution shown.
  final Resolution resolution;

  /// The instant the data was produced at (`loadedAt` of the answer of the use
  /// case). The state of the vote is judged at that instant: this layer reads
  /// no clock. A screen that stays open past the closing time shows the state
  /// as of the last load until it is refreshed.
  final Instant now;

  /// What a feature adds under the resolution, in the place of the line about
  /// the vote of the user. Without it the resolution is display only: it tells
  /// the vote the server recorded and offers nothing to do.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final closesAt = resolution.closesAt;
    final votingState = getVotingState(resolution, now);
    return Container(
      key: Key(resolutionTestId(resolution.id)),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.sm,
        children: [
          Text(
            resolution.title,
            style: const TextStyle(
              fontSize: AppFontSizes.body,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            resolution.description,
            style: const TextStyle(
              fontSize: AppFontSizes.body,
              color: AppColors.textPrimary,
            ),
          ),
          AppBadge(
            label: votingStateLabel(l10n, votingState),
            tone: votingStateTone(votingState),
          ),
          if (closesAt != null)
            Text(
              votingDateLabel(
                l10n,
                votingState,
                Formatters.of(context).dateTime(closesAt),
              ),
              style: const TextStyle(
                fontSize: AppFontSizes.caption,
                color: AppColors.textSecondary,
              ),
            ),
          actions ?? ResolutionVoteLine(resolution: resolution),
        ],
      ),
    );
  }
}
