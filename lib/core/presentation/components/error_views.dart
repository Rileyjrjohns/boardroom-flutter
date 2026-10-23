import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Takes the place of content that could not be loaded: the message for the
/// error, and a retry button when trying again can help. A session that is gone
/// or an item that does not exist is not fixed by asking again, so there is no
/// button for those: the failure is final for the screen.
class ErrorState extends ConsumerWidget {
  /// Creates the state for the failure with [code].
  const new({required this.code, this.onRetry, super.key});

  /// The code of the error, which decides the message and whether trying again
  /// can help.
  final String code;

  /// Called by the retry button, which is shown only when trying again can
  /// help.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(errorCatalogProvider);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.lg,
          children: [
            LiveText(
              message: catalog.messageOf(l10n, code),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppFontSizes.body,
                color: AppColors.textPrimary,
              ),
            ),
            if (catalog.isRetryableCode(code) && onRetry != null)
              AppButton(
                key: const Key(CoreTestIds.retryButton),
                title: l10n.coreStatesRetry,
                onPressed: onRetry,
              ),
          ],
        ),
      ),
    );
  }
}

/// An error next to content that is still there: a refresh that failed, a next
/// page that failed. Only an error that asking again can fix is shown this way,
/// with its retry button; any other is final and replaces the content (see
/// [ErrorState]).
class InlineError extends ConsumerWidget {
  /// Creates the error for the failure with [code].
  const new({required this.code, this.onRetry, super.key});

  /// The code of the error.
  final String code;

  /// Called by the retry button, shown only when trying again can help.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(errorCatalogProvider);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.md,
        children: [
          LiveText(
            message: catalog.messageOf(l10n, code),
            style: const TextStyle(
              fontSize: AppFontSizes.body,
              color: AppColors.danger,
            ),
          ),
          if (catalog.isRetryableCode(code) && onRetry != null)
            AppButton(
              key: const Key(CoreTestIds.retryButton),
              title: l10n.coreStatesRetry,
              onPressed: onRetry,
            ),
        ],
      ),
    );
  }
}
