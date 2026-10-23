import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/presentation/messages.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A person invited to the meeting, with their role.
class ParticipantRow extends StatelessWidget {
  /// Creates the row of [participant].
  const new({required this.participant, super.key});

  /// The person shown.
  final Participant participant;

  @override
  Widget build(BuildContext context) => Container(
    key: Key(participantTestId(participant.userId)),
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      spacing: AppSpacing.md,
      children: [
        Flexible(
          child: Text(
            participant.fullName,
            style: const TextStyle(
              fontSize: AppFontSizes.body,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          participantRoleLabel(AppLocalizations.of(context), participant.role),
          style: const TextStyle(
            fontSize: AppFontSizes.caption,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}
