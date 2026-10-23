import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/meetings/presentation/messages.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The line that tells the vote of the user on a resolution: the one the server
/// recorded, the one that waits to be sent, or none.
class ResolutionVoteLine extends StatelessWidget {
  /// Creates the line for [resolution].
  const new({
    required this.resolution,
    this.queuedChoice,
    this.unknown = false,
    super.key,
  });

  /// The resolution the line is about.
  final Resolution resolution;

  /// The choice of a vote of the user that waits to be sent, when whoever knows
  /// the outbox says so (the votes, through the slot of the resolution
  /// actions). The meetings know only the vote the server recorded.
  final VoteChoice? queuedChoice;

  /// Whether the vote of the user is not known yet: while the outbox is unknown
  /// the user may have a vote waiting that the line cannot tell, so saying "you
  /// have not voted" would be a guess and the line stays out.
  final bool unknown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recorded = resolution.recordedVote;
    final queued = queuedChoice;
    final String line;
    if (recorded != null) {
      line = l10n.meetingsMeetingResolutionYourVote(
        voteChoiceLabel(l10n, recorded),
      );
    } else if (queued != null) {
      line = l10n.meetingsMeetingResolutionYourVoteQueued(
        voteChoiceLabel(l10n, queued),
      );
    } else if (!unknown) {
      line = l10n.meetingsMeetingResolutionNoVote;
    } else {
      return const SizedBox.shrink();
    }
    return Text(
      line,
      style: const TextStyle(
        fontSize: AppFontSizes.caption,
        color: AppColors.textSecondary,
      ),
    );
  }
}
