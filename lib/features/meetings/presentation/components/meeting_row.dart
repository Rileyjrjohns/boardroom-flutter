import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A meeting in the list: title, date and time, location. It takes strings
/// and a callback, not objects, so that a row whose meeting has not changed
/// is not built again.
class MeetingRow extends StatelessWidget {
  /// Creates the row of the meeting with the id [id].
  const new({
    required this.id,
    required this.title,
    required this.when,
    required this.location,
    required this.onOpen,
    super.key,
  });

  /// The id of the meeting, in the test id of the row.
  final String id;

  /// The title of the meeting.
  final String title;

  /// The date and time, already formatted for the language of the user.
  final String when;

  /// Where the meeting takes place.
  final String location;

  /// Opens the meeting.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      hint: l10n.meetingsOpenHint,
      child: InkWell(
        key: Key(meetingRowTestId(id)),
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTargetMin),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.xs,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: AppFontSizes.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(when, style: _detail),
              Text(location, style: _detail),
            ],
          ),
        ),
      ),
    );
  }
}

const TextStyle _detail = TextStyle(
  fontSize: AppFontSizes.caption,
  color: AppColors.textSecondary,
);
