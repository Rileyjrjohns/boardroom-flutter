import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/app_dialog.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/auth/presentation/state/sign_out_action.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The confirmation of a sign-out. It says what the user needs to know before
/// leaving: they will have to sign in again, and the votes that still wait to
/// be sent are not lost, they stay on this device and go out after the next
/// sign-in. [pendingCount] is how many wait, if the screen knows: the lock
/// screen cannot (the outbox is out of reach while the app is locked), so it
/// passes null and the dialog says it in general terms.
///
/// While the sign-out is under way the dialog cannot be closed, neither by the
/// back gesture nor by Cancel. A session that cannot be forgotten is told in
/// the dialog, which can be confirmed again.
///
/// Open it with [showSignOutDialog], which also closes it as soon as the access
/// of the user changes, so that it never outlives the session it closes.
class SignOutDialog extends ConsumerWidget {
  /// Creates the dialog; [onDismiss] closes it.
  const new({required this.pendingCount, required this.onDismiss, super.key});

  /// How many votes wait in the outbox, null when the screen cannot know.
  final int? pendingCount;

  /// Called to close the dialog (Cancel, or the back gesture).
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final action = ref.watch(signOutActionProvider);
    final count = pendingCount;

    void dismiss() {
      if (action.isPending) {
        return;
      }
      ref.read(signOutActionProvider.notifier).reset();
      onDismiss();
    }

    const textStyle = TextStyle(
      fontSize: AppFontSizes.body,
      color: AppColors.textPrimary,
    );

    return AppDialog(
      key: const Key(AuthTestIds.signOutDialog),
      title: l10n.authSignOutTitle,
      onDismiss: action.isPending ? null : dismiss,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Text(l10n.authSignOutMessage, style: textStyle),
          if (count == null)
            KeyedSubtree(
              key: const Key(AuthTestIds.signOutPending),
              child: Text(l10n.authSignOutPendingUnknown, style: textStyle),
            )
          else if (count > 0)
            KeyedSubtree(
              key: const Key(AuthTestIds.signOutPending),
              child: Text(l10n.authSignOutPending(count), style: textStyle),
            ),
          if (action.failure != null)
            KeyedSubtree(
              key: const Key(AuthTestIds.signOutError),
              child: LiveText(
                message: l10n.authSignOutFailed,
                style: const TextStyle(
                  fontSize: AppFontSizes.body,
                  color: AppColors.danger,
                ),
              ),
            ),
        ],
      ),
      actions: [
        AppButton(
          key: const Key(AuthTestIds.signOutCancel),
          title: l10n.coreCommonCancel,
          variant: AppButtonVariant.secondary,
          onPressed: action.isPending ? null : dismiss,
        ),
        AppButton(
          key: const Key(AuthTestIds.signOutConfirm),
          title: action.isPending
              ? l10n.authSignOutSigningOut
              : l10n.authSignOutAction,
          variant: AppButtonVariant.danger,
          busy: action.isPending,
          onPressed: () => ref.read(signOutActionProvider.notifier).run(),
        ),
      ],
    );
  }
}

/// Shows the [SignOutDialog] over the current screen. It closes when the user
/// cancels and when the access changes (signed out, or locked after a sign-out
/// that failed), because the screen that asked for it is then gone.
Future<void> showSignOutDialog(BuildContext context, {int? pendingCount}) =>
    showAppDialog<void>(
      context,
      builder: (dialogContext) => Consumer(
        builder: (_, ref, _) {
          ref.listen(accessProvider, (_, _) {
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
          });
          return SignOutDialog(
            pendingCount: pendingCount,
            onDismiss: () => Navigator.of(dialogContext).pop(),
          );
        },
      ),
    );
