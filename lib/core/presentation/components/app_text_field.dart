import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:flutter/material.dart';

/// A text input with a visible label, an error under it, and the hints that
/// keyboards and password managers need. The label is also the accessibility
/// label, and the error is a live region, so that it is announced when it
/// appears. Pass the test id as `key`: it goes to the field, and
/// [errorKey] to the error line.
class AppTextField extends StatelessWidget {
  /// Creates the field.
  const new({
    required this.label,
    required this.controller,
    this.onChanged,
    this.error,
    this.errorKey,
    this.enabled = true,
    this.focusNode,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    super.key,
  });

  /// The translated name of the field, shown above it.
  final String label;

  /// The text being edited.
  final TextEditingController controller;

  /// Called on each edit.
  final ValueChanged<String>? onChanged;

  /// The translated reason the value is refused, shown under the field.
  final String? error;

  /// The key of the error line.
  final Key? errorKey;

  /// False while the form is being sent: the field keeps its value.
  final bool enabled;

  /// The focus of the field.
  final FocusNode? focusNode;

  /// Whether the text is hidden (a password).
  final bool obscureText;

  /// The kind of keyboard.
  final TextInputType? keyboardType;

  /// What the action key does ("next", "go").
  final TextInputAction? textInputAction;

  /// The autofill hints.
  final Iterable<String>? autofillHints;

  /// Called when the action key is pressed.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: AppSpacing.xs,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: AppFontSizes.body,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      Semantics(
        label: label,
        textField: true,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          obscureText: obscureText,
          enableSuggestions: !obscureText,
          autocorrect: false,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            filled: !enabled,
            fillColor: AppColors.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: BorderSide(
                color: error == null
                    ? AppColors.interactiveBorder
                    : AppColors.danger,
              ),
            ),
          ),
        ),
      ),
      if (error case final message?)
        KeyedSubtree(
          key: errorKey,
          child: LiveText(
            message: message,
            style: const TextStyle(
              fontSize: AppFontSizes.caption,
              color: AppColors.danger,
            ),
          ),
        ),
    ],
  );
}
