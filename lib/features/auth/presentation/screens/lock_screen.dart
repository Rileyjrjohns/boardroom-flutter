import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/demo_controls_view.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/components/status_banner.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/auth/presentation/components/session_notice.dart';
import 'package:boardroom/features/auth/presentation/components/sign_out_dialog.dart';
import 'package:boardroom/features/auth/presentation/error_messages.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/auth/presentation/state/unlock_action.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The lock screen (docs/spec/screens.md "Lock"): shown after a restored
/// session and whenever the lock is required on the way back from the
/// background. It shows nothing of the user, no name and no meeting: only that
/// the app is locked and the one action that unlocks it, which asks for the
/// biometric proof of the device. The prompt is never started on its own, the
/// user touches Unlock.
///
/// Each outcome of the prompt has its message (cancelled, not recognised,
/// locked out, unavailable, not enrolled). The rule when the biometrics cannot
/// be used is that nothing else unlocks the app: the only way forward is to
/// sign out and sign in again, which is why signing out is offered here,
/// always. The confirmation cannot say how many votes wait, since the outbox is
/// out of reach while the app is locked, and says in general terms that they
/// are kept. A device that is offline says so at the top, and so does the
/// switch of the demo in the dev configuration, as on the sign-in screen.
class LockScreen extends ConsumerWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final action = ref.watch(unlockActionProvider);
    final endedBy = ref.watch(
      accessControllerProvider.select((state) => state.sessionEndedBy),
    );
    final failure = action.failure;

    return Column(
      key: const Key(AuthTestIds.lockScreen),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ConnectionBanner(),
        const DemoOfflineSwitch(),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSizes.formMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.lg,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          l10n.authLockTitle,
                          style: const TextStyle(
                            fontSize: AppFontSizes.title,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        l10n.authLockMessage,
                        style: const TextStyle(
                          fontSize: AppFontSizes.body,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (endedBy != null) SessionNotice(code: endedBy),
                      if (failure != null)
                        KeyedSubtree(
                          key: const Key(AuthTestIds.lockError),
                          child: LiveText(
                            message: unlockErrorMessage(l10n, failure.code),
                            style: const TextStyle(
                              fontSize: AppFontSizes.body,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      AppButton(
                        key: const Key(AuthTestIds.lockUnlock),
                        title: action.isPending
                            ? l10n.authLockUnlocking
                            : l10n.authLockUnlock,
                        busy: action.isPending,
                        hint: l10n.authLockUnlockHint,
                        onPressed: () =>
                            ref.read(unlockActionProvider.notifier).run(),
                      ),
                      AppButton(
                        key: const Key(AuthTestIds.lockSignOut),
                        title: l10n.authSignOutAction,
                        variant: AppButtonVariant.secondary,
                        hint: l10n.authSignOutHint,
                        onPressed: () => showSignOutDialog(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
