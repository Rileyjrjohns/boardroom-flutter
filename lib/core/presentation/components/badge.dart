import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The colour family of a [AppBadge].
enum BadgeTone {
  /// Grey.
  neutral,

  /// Green.
  positive,

  /// Red: the confidential level, a count that needs attention.
  confidential,
}

/// A short label on a coloured pill: a status, a confidentiality level, a
/// role.
class AppBadge extends StatelessWidget {
  /// Creates a badge with the translated [label].
  const new({required this.label, this.tone = BadgeTone.neutral, super.key});

  /// The translated text.
  final String label;

  /// The colour family.
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      BadgeTone.neutral => (
        AppColors.neutralBadgeBackground,
        AppColors.neutralBadgeText,
      ),
      BadgeTone.positive => (
        AppColors.positiveBadgeBackground,
        AppColors.positiveBadgeText,
      ),
      BadgeTone.confidential => (
        AppColors.confidentialBadgeBackground,
        AppColors.confidentialBadgeText,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppFontSizes.caption,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
