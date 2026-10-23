import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shown instead of the app when the composition root could not be built: a
/// setting that names a way of wiring that does not exist, an address of the
/// API that cannot be used, or the local database that cannot be opened. It is
/// an error for the person who runs the app, not for a user, so it says what to
/// check and gives the technical code (docs/spec/screens.md "Startup failure").
class StartupFailureScreen extends StatelessWidget {
  /// Creates the screen for the error with [code].
  const new({required this.code, super.key});

  /// The code of the error that stopped the composition root. A technical
  /// value, shown as is.
  final String code;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      key: const Key(CoreTestIds.startupFailure),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.lg,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.coreStartupTitle,
                    style: const TextStyle(
                      fontSize: AppFontSizes.title,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  l10n.coreStartupMessage,
                  style: const TextStyle(fontSize: AppFontSizes.body),
                ),
                Text(
                  l10n.coreStartupCode(code),
                  style: const TextStyle(
                    fontSize: AppFontSizes.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
