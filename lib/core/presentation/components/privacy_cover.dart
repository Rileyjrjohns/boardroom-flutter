import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// What hides the content while the app is inactive or in the background, so
/// that the snapshot the system takes for the app switcher shows nothing
/// confidential. It shows the name of the app and nothing else, on a neutral
/// background: no title of a meeting, no name, no number. It fills the whole
/// window and is announced as hidden.
///
/// It is the Dart-level cover; the native screen protection of the document
/// viewer replaces it where the system takes the snapshot before the next
/// frame.
class PrivacyCover extends StatelessWidget {
  /// Creates the cover.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      key: const Key(CoreTestIds.privacyCover),
      container: true,
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l10n.corePrivacyHidden,
      child: ExcludeSemantics(
        child: ColoredBox(
          color: AppColors.surface,
          child: SizedBox.expand(
            child: Center(
              child: Text(
                l10n.coreAppName,
                textDirection: Directionality.of(context),
                style: const TextStyle(
                  fontSize: AppFontSizes.title,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
