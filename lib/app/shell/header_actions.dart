import 'package:boardroom/core/presentation/components/badge.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/navigation/navigate.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/auth/presentation/components/sign_out_dialog.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/features/votes/presentation/state/pending_votes.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The actions in the header of the meetings list: the votes that are not
/// settled, with a count when there are some, and signing out, which asks for a
/// confirmation first. The count is the outbox: the votes waiting to be sent
/// and the rejected ones the user has not acknowledged. It is shown only once
/// the outbox is read, and not while the read fails.
class HeaderActions extends ConsumerWidget {
  /// Creates the actions.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = Formatters.of(context);
    final outbox = ref.watch(pendingVotesProvider).value;
    final count = outbox == null
        ? 0
        : outbox.pending.length + outbox.rejected.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderAction(
          key: const Key(VotesTestIds.pendingVotesButton),
          semanticsLabel: count == 0
              ? l10n.votesPendingVotesOpen
              : l10n.votesPendingVotesOpenWithCount(formatters.number(count)),
          onPressed: () => openPendingVotes(context),
          children: [
            Text(l10n.votesPendingVotesOpen, style: _labelStyle),
            if (count > 0)
              KeyedSubtree(
                key: const Key(VotesTestIds.pendingVotesBadge),
                child: AppBadge(
                  label: formatters.number(count),
                  tone: BadgeTone.confidential,
                ),
              ),
          ],
        ),
        _HeaderAction(
          key: const Key(AuthTestIds.signOutButton),
          hint: l10n.authSignOutHint,
          onPressed: () =>
              showSignOutDialog(context, pendingCount: outbox?.pending.length),
          children: [Text(l10n.authSignOutAction, style: _labelStyle)],
        ),
      ],
    );
  }
}

const TextStyle _labelStyle = TextStyle(
  fontSize: AppFontSizes.body,
  fontWeight: FontWeight.w600,
  color: AppColors.primary,
);

class _HeaderAction extends StatelessWidget {
  const new({
    required this.children,
    required this.onPressed,
    this.semanticsLabel,
    this.hint,
    super.key,
  });

  final List<Widget> children;
  final VoidCallback onPressed;

  /// The accessible name when it differs from the visible text.
  final String? semanticsLabel;
  final String? hint;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticsLabel,
    hint: hint,
    excludeSemantics: semanticsLabel != null,
    child: InkWell(
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSizes.touchTargetMin,
          minWidth: AppSizes.touchTargetMin,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: AppSpacing.xs,
            children: children,
          ),
        ),
      ),
    ),
  );
}
