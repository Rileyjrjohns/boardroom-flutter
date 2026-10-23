import 'package:boardroom/core/presentation/components/error_views.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/query/query_failure.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/presentation/components/resolution_vote_line.dart';
import 'package:boardroom/features/meetings/presentation/state/meeting_query.dart';
import 'package:boardroom/features/votes/presentation/components/resolution_voting.dart';
import 'package:boardroom/features/votes/presentation/state/pending_votes.dart';
import 'package:boardroom/features/votes/presentation/state/resolution_vote.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the votes show under a resolution of a meeting, as the slot of the
/// meetings (`resolutionActionsProvider`) takes it: the line about the vote of
/// the user (the one the server recorded, the one that waits to be sent, or
/// none, and nothing while it is not known) and what the user can do about it
/// and why they cannot when they cannot (see `ResolutionVoting`).
///
/// The state of the votes of the user is read once for every meeting (who they
/// are, what waits in their outbox: two queries shared by every resolution),
/// and each resolution gets its view of it. A failure to read it is told once,
/// above the first resolution of the meeting, with a way to try again, and the
/// resolutions say nothing of the vote meanwhile.
Widget voteResolutionActions(
  BuildContext context, {
  required Meeting meeting,
  required Resolution resolution,
}) => VoteResolutionActions(meeting: meeting, resolution: resolution);

/// The widget behind [voteResolutionActions].
class VoteResolutionActions extends ConsumerWidget {
  /// Creates the block of [resolution] in [meeting].
  const new({required this.meeting, required this.resolution, super.key});

  /// The meeting as it was loaded.
  final Meeting meeting;

  /// The resolution.
  final Resolution resolution;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(errorCatalogProvider);
    final voter = ref.watch(voterProvider);
    final outbox = ref.watch(pendingVotesProvider);
    final loadedAt = ref
        .watch(meetingQueryProvider(meeting.id))
        .value
        ?.loadedAt;

    final voterId = voter.value?.id;
    final content = outbox.value;
    final ResolutionVoteView view;
    if (voterId != null && content != null) {
      view = resolutionVoteView(
        ResolutionVoteInput(
          meeting: meeting,
          resolution: resolution,
          voterId: voterId,
          outbox: content,
          // The meeting is judged at the instant it was loaded at; the clock is
          // only the fallback when the meeting is not in the query any more.
          now: loadedAt ?? ref.read(clockProvider).now(),
        ),
      );
    } else if (voter.hasError || outbox.hasError) {
      view = const VoteViewUnavailable();
    } else {
      view = const VoteViewLoading();
    }

    final failed = voter.hasError && voterId == null
        ? voter.error
        : (outbox.hasError && content == null ? outbox.error : null);
    final showError = failed != null && _isFirstResolution(meeting, resolution);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showError)
          InlineError(
            key: const Key(VotesTestIds.votingError),
            code: errorCodeOf(failed, catalog),
            onRetry: () {
              if (voterId == null) {
                ref.invalidate(voterProvider);
              }
              if (content == null) {
                ref.invalidate(pendingVotesProvider);
              }
            },
          ),
        ResolutionVoteLine(
          resolution: resolution,
          queuedChoice: switch (view) {
            VoteViewQueued(:final choice) => choice,
            _ => null,
          },
          unknown: view is VoteViewLoading || view is VoteViewUnavailable,
        ),
        ResolutionVoting(
          meetingId: meeting.id,
          resolution: resolution,
          view: view,
        ),
      ],
    );
  }
}

/// Whether [resolution] is the first one of the agenda of [meeting]: the votes
/// error is told there, once for the meeting.
bool _isFirstResolution(Meeting meeting, Resolution resolution) {
  for (final item in meeting.agenda) {
    final first = item.resolution;
    if (first != null) {
      return first.id == resolution.id;
    }
  }
  return false;
}
