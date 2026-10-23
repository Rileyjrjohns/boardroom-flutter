import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why the user is on the sign-in or the lock screen when they did not ask to
/// be: their session expired, the server refused it, another user signed in,
/// the app locked. It is announced when it appears, and it is the same text as
/// when the failure is met anywhere else.
class SessionNotice extends ConsumerWidget {
  /// Creates the notice for the failure with [code].
  const new({required this.code, super.key});

  /// The failure that sent the user back to this screen.
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(errorCatalogProvider);
    return KeyedSubtree(
      key: const Key(AuthTestIds.sessionNotice),
      child: LiveText(
        message: catalog.messageOf(AppLocalizations.of(context), code),
        style: const TextStyle(
          fontSize: AppFontSizes.body,
          color: AppColors.danger,
        ),
      ),
    );
  }
}
