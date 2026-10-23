// Every test id of the app, put together: the core's and each feature's, which
// each declares its own. The composition is the one place that sees them all,
// so it is where the registry that the specification is compared with is made
// (`test/tool/spec_conformance_test.dart`). Pure Dart.
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/features/documents/presentation/test_ids.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/features/votes/presentation/test_ids.dart';

export 'package:boardroom/core/presentation/test_ids.dart'
    show demoAccountTestId;
export 'package:boardroom/features/meetings/presentation/test_ids.dart'
    show
        agendaItemTestId,
        documentTestId,
        meetingRowTestId,
        meetingRowTestIdPrefix,
        participantTestId,
        periodOptionTestId,
        resolutionTestId;
export 'package:boardroom/features/votes/presentation/test_ids.dart'
    show
        acknowledgeTestId,
        openVoteMeetingTestId,
        pendingVoteTestId,
        rejectedVoteTestId,
        voteChoiceTestId,
        voteChoicesTestId,
        voteNoticeTestId,
        voteOutcomeTestId;

/// The fixed test ids of the whole app, by constant name. A test checks that no
/// two share a name or a value, and that they are the ones of
/// docs/spec/screens.md.
const Map<String, String> testIds = {
  // Core.
  'statusBanner': CoreTestIds.statusBanner,
  'offlineBanner': CoreTestIds.offlineBanner,
  'staleBanner': CoreTestIds.staleBanner,
  'retryButton': CoreTestIds.retryButton,
  'refreshError': CoreTestIds.refreshError,
  'demoPanel': CoreTestIds.demoPanel,
  'demoAccounts': CoreTestIds.demoAccounts,
  'demoOfflineSwitch': CoreTestIds.demoOfflineSwitch,
  'privacyCover': CoreTestIds.privacyCover,
  'appContent': CoreTestIds.appContent,
  'localDataResetNotice': CoreTestIds.localDataResetNotice,
  'localDataResetDismiss': CoreTestIds.localDataResetDismiss,
  'startupLoading': CoreTestIds.startupLoading,
  'startupFailure': CoreTestIds.startupFailure,
  'errorBoundary': CoreTestIds.errorBoundary,
  // Auth.
  'restoreError': AuthTestIds.restoreError,
  'restoreForget': AuthTestIds.restoreForget,
  'restoreForgetError': AuthTestIds.restoreForgetError,
  'sessionNotice': AuthTestIds.sessionNotice,
  'signInScreen': AuthTestIds.signInScreen,
  'signInEmail': AuthTestIds.signInEmail,
  'signInEmailError': AuthTestIds.signInEmailError,
  'signInPassword': AuthTestIds.signInPassword,
  'signInPasswordError': AuthTestIds.signInPasswordError,
  'signInError': AuthTestIds.signInError,
  'signInSubmit': AuthTestIds.signInSubmit,
  'lockScreen': AuthTestIds.lockScreen,
  'lockUnlock': AuthTestIds.lockUnlock,
  'lockError': AuthTestIds.lockError,
  'lockSignOut': AuthTestIds.lockSignOut,
  'signOutButton': AuthTestIds.signOutButton,
  'signOutDialog': AuthTestIds.signOutDialog,
  'signOutPending': AuthTestIds.signOutPending,
  'signOutError': AuthTestIds.signOutError,
  'signOutConfirm': AuthTestIds.signOutConfirm,
  'signOutCancel': AuthTestIds.signOutCancel,
  // Meetings.
  'meetingsList': MeetingsTestIds.meetingsList,
  'meetingsLoading': MeetingsTestIds.meetingsLoading,
  'meetingsEmpty': MeetingsTestIds.meetingsEmpty,
  'meetingsError': MeetingsTestIds.meetingsError,
  'meetingsEnd': MeetingsTestIds.meetingsEnd,
  'meetingsLoadingMore': MeetingsTestIds.meetingsLoadingMore,
  'meetingsLoadMoreError': MeetingsTestIds.meetingsLoadMoreError,
  'meetingDetail': MeetingsTestIds.meetingDetail,
  'meetingLoading': MeetingsTestIds.meetingLoading,
  'meetingError': MeetingsTestIds.meetingError,
  'meetingNotFound': MeetingsTestIds.meetingNotFound,
  'meetingTitle': MeetingsTestIds.meetingTitle,
  'agendaSection': MeetingsTestIds.agendaSection,
  'documentsSection': MeetingsTestIds.documentsSection,
  'participantsSection': MeetingsTestIds.participantsSection,
  // Documents.
  'documentScreen': DocumentsTestIds.documentScreen,
  'documentNotFound': DocumentsTestIds.documentNotFound,
  'documentLoading': DocumentsTestIds.documentLoading,
  'documentError': DocumentsTestIds.documentError,
  'documentTitle': DocumentsTestIds.documentTitle,
  'documentProtectedBadge': DocumentsTestIds.documentProtectedBadge,
  'documentPdf': DocumentsTestIds.documentPdf,
  'documentPdfLoading': DocumentsTestIds.documentPdfLoading,
  'documentPdfError': DocumentsTestIds.documentPdfError,
  'documentPageIndicator': DocumentsTestIds.documentPageIndicator,
  'documentWatermark': DocumentsTestIds.documentWatermark,
  'documentWatermarkTile': DocumentsTestIds.documentWatermarkTile,
  'documentSecureContent': DocumentsTestIds.documentSecureContent,
  'documentCaptureNotice': DocumentsTestIds.documentCaptureNotice,
  'documentCaptureDismiss': DocumentsTestIds.documentCaptureDismiss,
  // Votes.
  'pendingVotesButton': VotesTestIds.pendingVotesButton,
  'pendingVotesBadge': VotesTestIds.pendingVotesBadge,
  'pendingVotesScreen': VotesTestIds.pendingVotesScreen,
  'pendingVotesLoading': VotesTestIds.pendingVotesLoading,
  'pendingVotesError': VotesTestIds.pendingVotesError,
  'pendingVotesEmpty': VotesTestIds.pendingVotesEmpty,
  'pendingVotesWaiting': VotesTestIds.pendingVotesWaiting,
  'pendingVotesRejected': VotesTestIds.pendingVotesRejected,
  'unreadableVotes': VotesTestIds.unreadableVotes,
  'unreadableVotesDiscard': VotesTestIds.unreadableVotesDiscard,
  'unreadableVotesDialog': VotesTestIds.unreadableVotesDialog,
  'unreadableVotesConfirm': VotesTestIds.unreadableVotesConfirm,
  'unreadableVotesCancel': VotesTestIds.unreadableVotesCancel,
  'unreadableVotesError': VotesTestIds.unreadableVotesError,
  'syncSummary': VotesTestIds.syncSummary,
  'syncSummaryDismiss': VotesTestIds.syncSummaryDismiss,
  'votingLoading': VotesTestIds.votingLoading,
  'votingError': VotesTestIds.votingError,
  'voteDialog': VotesTestIds.voteDialog,
  'voteDialogChoice': VotesTestIds.voteDialogChoice,
  'voteDialogFinal': VotesTestIds.voteDialogFinal,
  'voteDialogOffline': VotesTestIds.voteDialogOffline,
  'voteDialogError': VotesTestIds.voteDialogError,
  'voteConfirm': VotesTestIds.voteConfirm,
  'voteCancel': VotesTestIds.voteCancel,
  'voteClose': VotesTestIds.voteClose,
};
