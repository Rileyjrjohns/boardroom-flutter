import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:flutter/material.dart';

/// A spinner that tells the screen reader what it is waiting for: a progress
/// indicator with a label, announced when it appears.
class LoadingState extends StatelessWidget {
  /// Creates the state; [label] is the translated name of what is loading.
  const new({required this.label, super.key});

  /// The translated name of what is loading, read by the screen reader.
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Semantics(
        label: label,
        liveRegion: true,
        child: const CircularProgressIndicator(color: AppColors.primary),
      ),
    ),
  );
}
