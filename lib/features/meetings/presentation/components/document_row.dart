import 'package:boardroom/core/presentation/components/badge.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/presentation/messages.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A document attached to a meeting: title, confidentiality, number of pages.
/// The whole row is a button that opens the document. A screen reader hears it
/// as one thing, with a name that says all three facts (the visible texts
/// inside a button are not read one by one), and a hint that says where it
/// leads.
class DocumentRow extends StatelessWidget {
  /// Creates the row of [document].
  const new({required this.document, required this.onOpen, super.key});

  /// The document shown.
  final Document document;

  /// Opens the document in the viewer.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = l10n.meetingsMeetingPageCount(document.pageCount);
    final confidentiality = confidentialityLabel(
      l10n,
      document.confidentiality,
    );
    return Semantics(
      button: true,
      label: l10n.meetingsMeetingDocumentLabel(
        document.title,
        confidentiality,
        pages,
      ),
      hint: l10n.meetingsMeetingOpenDocumentHint,
      excludeSemantics: true,
      onTap: onOpen,
      child: InkWell(
        key: Key(documentTestId(document.id)),
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTargetMin),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.sm,
            children: [
              Text(
                document.title,
                style: const TextStyle(
                  fontSize: AppFontSizes.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Row(
                spacing: AppSpacing.md,
                children: [
                  AppBadge(
                    label: confidentiality,
                    tone: confidentialityTone(document.confidentiality),
                  ),
                  Text(
                    pages,
                    style: const TextStyle(
                      fontSize: AppFontSizes.caption,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
