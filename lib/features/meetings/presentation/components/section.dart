import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:flutter/material.dart';

/// A titled block of the meeting detail. The title is a header for the screen
/// reader; [testId] is the key of the block.
class MeetingSection extends StatelessWidget {
  /// Creates a section with the translated [title].
  const new({
    required this.title,
    required this.testId,
    required this.children,
    super.key,
  });

  /// The translated title.
  final String title;

  /// The test id of the block.
  final String testId;

  /// The content of the section.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    key: Key(testId),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.lg,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.md,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: const TextStyle(
              fontSize: AppFontSizes.subtitle,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        ...children,
      ],
    ),
  );
}
