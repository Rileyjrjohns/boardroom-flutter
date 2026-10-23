import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:flutter/material.dart';

/// What a button is for: the main action of a screen, a quiet one, or one that
/// cannot be undone.
enum AppButtonVariant {
  /// The main action.
  primary,

  /// A quiet action.
  secondary,

  /// An action that cannot be undone.
  danger,
}

/// A button with a visible text, at least as big as the touch target the
/// platforms ask for. While [busy] it shows a spinner, cannot be pressed
/// again and says it is busy: the title should then say what is going on
/// ("Signing in").
class AppButton extends StatelessWidget {
  /// Creates a button with the translated [title].
  const new({
    required this.title,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.busy = false,
    this.hint,
    super.key,
  });

  /// The translated text of the button.
  final String title;

  /// Called when pressed; null disables the button.
  final VoidCallback? onPressed;

  /// The kind of action.
  final AppButtonVariant variant;

  /// Whether the action is under way.
  final bool busy;

  /// The translated sentence that says what the button leads to, when the
  /// title does not.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy) ...[
          SizedBox.square(
            dimension: AppFontSizes.body,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _spinnerColor,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(child: Text(title, textAlign: TextAlign.center)),
      ],
    );
    const minimum = Size(AppSizes.touchTargetMin, AppSizes.touchTargetMin);
    final action = switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(minimumSize: minimum),
        child: child,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          minimumSize: minimum,
          side: const BorderSide(color: AppColors.primary),
        ),
        child: child,
      ),
      AppButtonVariant.danger => FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          minimumSize: minimum,
          backgroundColor: AppColors.danger,
        ),
        child: child,
      ),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      hint: hint,
      label: title,
      excludeSemantics: true,
      onTap: enabled ? onPressed : null,
      child: action,
    );
  }

  Color get _spinnerColor => variant == AppButtonVariant.secondary
      ? AppColors.primary
      : AppColors.onPrimary;
}
