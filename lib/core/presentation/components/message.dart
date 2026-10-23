import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:flutter/material.dart';

/// A line of secondary text on its own: an empty list, the end of a list, a
/// "not found".
class Message extends StatelessWidget {
  /// Creates the message; [message] is the translated text.
  const new({required this.message, this.centered = false, super.key});

  /// The translated text.
  final String message;

  /// Centred in the space it is given (an empty list), or in line (the end of a
  /// list).
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final text = Padding(
      padding: EdgeInsets.all(centered ? AppSpacing.xl : AppSpacing.lg),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: AppFontSizes.body,
          color: AppColors.textSecondary,
        ),
      ),
    );
    return centered ? Center(child: text) : text;
  }
}
