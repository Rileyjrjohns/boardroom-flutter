import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/documents/presentation/error_messages.dart';
import 'package:boardroom/features/documents/presentation/state/capture_watch.dart';
import 'package:boardroom/features/documents/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

/// Tells the reader that a screenshot or a recording of the screen was seen,
/// and that it was recorded. Calm on purpose: it states what happened, it does
/// not accuse (a reader may well have taken the screenshot by accident). It is
/// announced to the screen reader when it appears, and again for each new
/// capture, since the words are the same: the sequence number is the key of the
/// live text, which makes each notice a new one for the live region.
class CaptureNotice extends StatelessWidget {
  /// Creates the strip for [notice].
  const new({required this.notice, required this.onDismiss, super.key});

  /// The capture to tell.
  final CaptureNoticeValue notice;

  /// Called by the dismiss button.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = captureNoticeMessage(l10n, notice.kind);
    return Container(
      width: double.infinity,
      color: AppColors.warningBackground,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.sm,
        children: [
          if (message != null)
            KeyedSubtree(
              key: const Key(DocumentsTestIds.documentCaptureNotice),
              child: LiveText(
                key: ValueKey(notice.sequence),
                message: message,
                style: const TextStyle(
                  fontSize: AppFontSizes.caption,
                  color: AppColors.warningText,
                ),
              ),
            ),
          AppButton(
            key: const Key(DocumentsTestIds.documentCaptureDismiss),
            title: l10n.coreBannerDismiss,
            variant: AppButtonVariant.secondary,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
