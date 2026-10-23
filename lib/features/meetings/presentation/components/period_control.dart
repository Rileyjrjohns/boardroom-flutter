import 'dart:ui' show SemanticsRole;

import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/presentation/messages.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The segmented control that chooses the period of the meetings list: a tab
/// list, labelled, whose options say which one is selected.
class PeriodControl extends StatelessWidget {
  /// Creates the control with [selected] chosen.
  const new({required this.selected, required this.onChanged, super.key});

  /// The period shown.
  final MeetingPeriod selected;

  /// Called with the period the user chooses.
  final ValueChanged<MeetingPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      role: SemanticsRole.tabBar,
      container: true,
      label: l10n.meetingsPeriodLabel,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              for (final period in MeetingPeriod.values)
                Expanded(
                  child: _Option(
                    label: meetingPeriodLabel(l10n, period),
                    testId: periodOptionTestId(period.value),
                    selected: period == selected,
                    onTap: () => onChanged(period),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const new({
    required this.label,
    required this.testId,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String testId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    role: SemanticsRole.tab,
    selected: selected,
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        key: Key(testId),
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTargetMin),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppFontSizes.body,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.onPrimary : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
