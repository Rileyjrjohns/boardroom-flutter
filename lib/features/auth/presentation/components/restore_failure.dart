import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/error_views.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/auth/presentation/state/sign_out_action.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the user sees when the session saved on the device cannot be read at
/// the start: the failure, and a way to ask again. Asking again is not always
/// enough (a stored session that stays unreadable would keep the user on this
/// screen for good), so there is a way out as well: signing out on this device,
/// which forgets the session and goes to the sign-in screen. It is behind a
/// sentence that says what it does, and it keeps the votes that wait to be
/// sent, like any sign-out. A sign-out that fails says so and can be asked
/// again.
class RestoreFailure extends ConsumerWidget {
  /// Creates the screen for the failure [error]; [onRetry] asks again.
  const new({required this.error, required this.onRetry, super.key});

  /// Why the session saved on this device could not be read.
  final StorageReadFailedError error;

  /// Asks again.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final signOut = ref.watch(signOutActionProvider);
    return Column(
      children: [
        Expanded(
          child: KeyedSubtree(
            key: const Key(AuthTestIds.restoreError),
            child: ErrorState(code: error.code, onRetry: onRetry),
          ),
        ),
        Align(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSizes.formMaxWidth),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.md,
                children: [
                  Text(
                    l10n.coreStartupForgetExplanation,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: AppFontSizes.body,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (signOut.failure != null)
                    KeyedSubtree(
                      key: const Key(AuthTestIds.restoreForgetError),
                      child: LiveText(
                        message: l10n.authSignOutFailed,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: AppFontSizes.body,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  AppButton(
                    key: const Key(AuthTestIds.restoreForget),
                    title: signOut.isPending
                        ? l10n.authSignOutSigningOut
                        : l10n.coreStartupForget,
                    variant: AppButtonVariant.secondary,
                    busy: signOut.isPending,
                    onPressed: () =>
                        ref.read(signOutActionProvider.notifier).run(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
