import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/documents/presentation/error_messages.dart';
import 'package:boardroom/features/documents/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Takes the place of a document that could not be opened: the message for the
/// error, in the words of a document (a document that is not on the device
/// cannot be read offline, a document that does not exist is not a meeting that
/// does not), and a button to try again when trying again can help.
class DocumentErrorState extends ConsumerWidget {
  /// Creates the state for a failure with [code].
  const new({required this.code, required this.onRetry, super.key});

  /// Why the document could not be opened, which decides the message and
  /// whether trying again can help.
  final String code;

  /// Called by the retry button, which is shown only when trying again can
  /// help.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(errorCatalogProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.lg,
          children: [
            KeyedSubtree(
              key: const Key(DocumentsTestIds.documentError),
              child: LiveText(
                message: documentErrorMessage(l10n, code),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppFontSizes.body,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (catalog.isRetryableCode(code))
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
