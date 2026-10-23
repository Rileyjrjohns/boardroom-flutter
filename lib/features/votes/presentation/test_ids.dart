// The test ids of the votes: pending votes, voting and the vote dialog,
// declared by the feature that owns the screens and put together with the
// others by `lib/app/test_ids.dart`. Pure Dart, so that the conformance test of
// the specification can read them. The widgets set them as `Key(id)`; the
// values are the ones of docs/spec/screens.md.

/// The test ids of the votes: pending votes, voting and the vote dialog.
abstract final class VotesTestIds {
  /// The pending votes button of the header.
  static const String pendingVotesButton = 'pending-votes-button';

  /// The count badge of that button.
  static const String pendingVotesBadge = 'pending-votes-badge';

  /// The pending votes screen.
  static const String pendingVotesScreen = 'pending-votes-screen';

  /// The outbox read is pending.
  static const String pendingVotesLoading = 'pending-votes-loading';

  /// A final error.
  static const String pendingVotesError = 'pending-votes-error';

  /// No pending and no rejected vote.
  static const String pendingVotesEmpty = 'pending-votes-empty';

  /// The waiting section.
  static const String pendingVotesWaiting = 'pending-votes-waiting';

  /// The rejected section.
  static const String pendingVotesRejected = 'pending-votes-rejected';

  /// The unreadable votes notice.
  static const String unreadableVotes = 'unreadable-votes';

  /// The discard button of the notice.
  static const String unreadableVotesDiscard = 'unreadable-votes-discard';

  /// The confirmation dialog.
  static const String unreadableVotesDialog = 'unreadable-votes-dialog';

  /// Its confirm button.
  static const String unreadableVotesConfirm = 'unreadable-votes-confirm';

  /// Its cancel button.
  static const String unreadableVotesCancel = 'unreadable-votes-cancel';

  /// The discard failed.
  static const String unreadableVotesError = 'unreadable-votes-error';

  /// The sync summary of the banner.
  static const String syncSummary = 'sync-summary';

  /// Its dismiss button.
  static const String syncSummaryDismiss = 'sync-summary-dismiss';

  /// A resolution whose vote view is loading.
  static const String votingLoading = 'voting-loading';

  /// The votes of the meeting are unavailable.
  static const String votingError = 'voting-error';

  /// The vote dialog.
  static const String voteDialog = 'vote-dialog';

  /// The choice under review.
  static const String voteDialogChoice = 'vote-dialog-choice';

  /// The vote is final.
  static const String voteDialogFinal = 'vote-dialog-final';

  /// The device is offline.
  static const String voteDialogOffline = 'vote-dialog-offline';

  /// The last attempt failed.
  static const String voteDialogError = 'vote-dialog-error';

  /// The confirm button.
  static const String voteConfirm = 'vote-confirm';

  /// The cancel button.
  static const String voteCancel = 'vote-cancel';

  /// The close button.
  static const String voteClose = 'vote-close';
}

/// The choice buttons of a resolution, by resolution id.
String voteChoicesTestId(String resolutionId) => 'vote-choices-$resolutionId';

/// One choice button; [choice] is `for`, `against` or `abstain` (the `value` of
/// the `VoteChoice`).
String voteChoiceTestId(String resolutionId, String choice) =>
    'vote-choice-$resolutionId-$choice';

/// The reason text or the rejection line of a resolution.
String voteNoticeTestId(String resolutionId) => 'vote-notice-$resolutionId';

/// The outcome line of a resolution.
String voteOutcomeTestId(String resolutionId) => 'vote-outcome-$resolutionId';

/// The acknowledge button of a rejected vote.
String acknowledgeTestId(String resolutionId) => 'acknowledge-$resolutionId';

/// A row of the waiting section of the pending votes screen.
String pendingVoteTestId(String resolutionId) => 'pending-vote-$resolutionId';

/// A row of the rejected section of the pending votes screen.
String rejectedVoteTestId(String resolutionId) => 'rejected-vote-$resolutionId';

/// The button of a row that opens the meeting of the vote.
String openVoteMeetingTestId(String resolutionId) =>
    'open-vote-meeting-$resolutionId';
