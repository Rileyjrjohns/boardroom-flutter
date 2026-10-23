import 'dart:async';

import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/app_dialog.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/use_cases/cast_vote.dart';
import 'package:boardroom/features/votes/presentation/components/acknowledge_button.dart';
import 'package:boardroom/features/votes/presentation/components/vote_dialog.dart';
import 'package:boardroom/features/votes/presentation/error_messages.dart';
import 'package:boardroom/features/votes/presentation/state/resolution_vote.dart';
import 'package:boardroom/features/votes/presentation/state/vote_actions.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The choices, in the order they are offered.
const List<VoteChoice> voteChoices = [
  VoteChoice.forChoice,
  VoteChoice.against,
  VoteChoice.abstain,
];

/// What the user can do about the vote on a resolution, and why they cannot
/// when they cannot:
///
/// - eligible: the three choices. Touching one opens the confirmation step
///   (`VoteDialog`), which is where a vote is cast;
/// - a vote waiting to be sent: said by the line of the resolution, and by the
///   message that it is saved on this device, for as long as it waits: when it
///   is sent or refused the view changes and the message goes with it;
/// - a vote that was rejected: why, and the button that acknowledges it;
/// - ineligible: the reason the rule gives (a role without a vote, a closed
///   vote, a vote already cast), as text, with no control that would do
///   nothing.
///
/// The state of the cast lives here and not in the part that shows the choices,
/// because casting a vote changes what is shown: once the vote is recorded or
/// queued the choices are gone, and the confirmation must still be there to
/// close itself when the screen shows the new state, and the message that says
/// a vote was recorded must outlive the choices.
class ResolutionVoting extends ConsumerStatefulWidget {
  /// Creates the block of [resolution] of the meeting [meetingId], for [view].
  const new({
    required this.meetingId,
    required this.resolution,
    required this.view,
    super.key,
  });

  /// The meeting the resolution belongs to.
  final MeetingId meetingId;

  /// The resolution voted on.
  final Resolution resolution;

  /// Where the vote of the user stands.
  final ResolutionVoteView view;

  @override
  ConsumerState<ResolutionVoting> createState() => _ResolutionVotingState();
}

class _ResolutionVotingState extends ConsumerState<ResolutionVoting> {
  CastVoteStatus? _outcome;
  NavigatorState? _dialogNavigator;

  ResolutionId get _resolutionId => widget.resolution.id;

  CastVoteActionProvider get _action => castVoteActionProvider(_resolutionId);

  void _choose(VoteChoice choice) {
    ref.read(_action.notifier).reset();
    setState(() => _outcome = null);
    // The dialog is opened on the root navigator, and closed there.
    final navigator = Navigator.of(context, rootNavigator: true);
    _dialogNavigator = navigator;
    unawaited(
      showAppDialog<void>(
        context,
        builder: (_) => _VoteDialogHost(
          choice: choice,
          resolution: widget.resolution,
          onConfirm: () => _confirm(choice),
          onDismiss: _dismiss,
        ),
      ).whenComplete(() {
        _dialogNavigator = null;
      }),
    );
  }

  void _confirm(VoteChoice choice) {
    unawaited(
      ref
          .read(_action.notifier)
          .run(
            meetingId: widget.meetingId,
            choice: choice,
            onCast: (outcome) {
              if (mounted) {
                setState(() => _outcome = outcome.status);
              }
              _closeDialog();
            },
          ),
    );
  }

  void _dismiss() {
    ref.read(_action.notifier).reset();
    _closeDialog();
  }

  void _closeDialog() {
    final navigator = _dialogNavigator;
    _dialogNavigator = null;
    if (navigator != null && navigator.mounted) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Keeps the state of the cast while the confirmation is up.
    ref.listen(_action, (_, _) {});
    final outcome = _outcome;
    final outcomeText = outcome == null
        ? null
        : castOutcomeMessage(l10n, outcome);
    final view = widget.view;
    final resolutionId = _resolutionId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        if (outcomeText != null)
          KeyedSubtree(
            key: Key(voteOutcomeTestId(resolutionId)),
            child: LiveText(message: outcomeText, style: _outcomeStyle),
          ),
        switch (view) {
          VoteViewLoading() => KeyedSubtree(
            key: const Key(VotesTestIds.votingLoading),
            child: Semantics(
              label: l10n.votesVotingLoading,
              liveRegion: true,
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          ),
          VoteViewUnavailable() => const SizedBox.shrink(),
          VoteViewQueued() => KeyedSubtree(
            key: Key(voteOutcomeTestId(resolutionId)),
            child: LiveText(
              message: l10n.votesVotingQueued,
              style: _outcomeStyle,
            ),
          ),
          VoteViewEligible() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.sm,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.votesVotingChoose,
                  style: const TextStyle(
                    fontSize: AppFontSizes.body,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              // One below the other, each as wide as the screen: side by side,
              // a third of the width left too little for "Abstention" (French)
              // on a narrow phone, which broke the word in two, and a larger
              // text size would do the same in any language.
              Column(
                key: Key(voteChoicesTestId(resolutionId)),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.sm,
                children: [
                  for (final choice in voteChoices)
                    AppButton(
                      key: Key(voteChoiceTestId(resolutionId, choice.value)),
                      title: voteChoiceLabel(l10n, choice),
                      variant: AppButtonVariant.secondary,
                      hint: l10n.votesVotingChoiceHint,
                      onPressed: () => _choose(choice),
                    ),
                ],
              ),
            ],
          ),
          VoteViewRejected(:final reason) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.sm,
            children: [
              KeyedSubtree(
                key: Key(voteNoticeTestId(resolutionId)),
                child: LiveText(
                  message: rejectedVoteMessage(l10n, reason),
                  style: const TextStyle(
                    fontSize: AppFontSizes.body,
                    color: AppColors.danger,
                  ),
                ),
              ),
              AcknowledgeButton(resolutionId: resolutionId),
            ],
          ),
          VoteViewIneligible(:final error, :final role) => Text(
            role != null
                ? l10n.votesVotingNoVotingRightsAs(
                    participantRoleLabel(l10n, role),
                  )
                : votingReasonMessage(l10n, error),
            key: Key(voteNoticeTestId(resolutionId)),
            style: const TextStyle(
              fontSize: AppFontSizes.body,
              color: AppColors.textSecondary,
            ),
          ),
        },
      ],
    );
  }
}

const TextStyle _outcomeStyle = TextStyle(
  fontSize: AppFontSizes.body,
  fontWeight: FontWeight.w600,
  color: AppColors.positiveBadgeText,
);

/// The dialog, kept up to date with the state of the cast and of the
/// connection, which change while it is open.
class _VoteDialogHost extends ConsumerWidget {
  const new({
    required this.choice,
    required this.resolution,
    required this.onConfirm,
    required this.onDismiss,
  });

  final VoteChoice choice;
  final Resolution resolution;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(castVoteActionProvider(resolution.id));
    final offline =
        ref.watch(connectivityStateProvider) == ConnectivityStatus.offline;
    return VoteDialog(
      choice: choice,
      resolutionTitle: resolution.title,
      offline: offline,
      pending: action.isPending,
      failure: action.failure,
      onConfirm: onConfirm,
      onDismiss: onDismiss,
    );
  }
}
