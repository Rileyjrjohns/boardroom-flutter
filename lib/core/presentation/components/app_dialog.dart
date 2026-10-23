import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:flutter/material.dart';

/// A window over the screen that asks something of the user: a confirmation,
/// mostly. The [title] is announced as a header, [content] is the body (text,
/// mostly) and [actions] are the buttons in the order they are read, the safe
/// one first. [onDismiss] is asked for by the back gesture or the back button;
/// nothing else dismisses it (a tap outside does not), and a dialog whose
/// action
/// is under way passes null to refuse it.
///
/// Open it with [showAppDialog]. The privacy cover of `ContentHost` is drawn
/// over the navigator, so it covers the dialog too.
class AppDialog extends StatelessWidget {
  /// Creates the dialog.
  const new({
    required this.title,
    required this.content,
    required this.actions,
    this.onDismiss,
    super.key,
  });

  /// The translated title.
  final String title;

  /// The body.
  final Widget content;

  /// The buttons.
  final List<Widget> actions;

  /// Asked for by the back gesture; null refuses it.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        onDismiss?.call();
      }
    },
    child: Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.dialogMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                content,
                const SizedBox(height: AppSpacing.sm),
                ...actions.expand(
                  (action) => [action, const SizedBox(height: AppSpacing.sm)],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shows the dialog built by [builder] over the current screen. The dialog is
/// not dismissed by a tap outside; it closes with `Navigator.pop`.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  barrierDismissible: false,
  builder: builder,
);
