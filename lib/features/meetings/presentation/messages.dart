import 'package:boardroom/core/presentation/components/badge.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/policies/voting_state.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/l10n/app_localizations.dart';

// The domain speaks in codes (a role, a level, a voting state) and carries no
// text. These functions are where a code of the meetings becomes a text, and
// the colour of its badge. Each switch is exhaustive over the whole set of its
// codes, so a code added to the domain without a text fails the analysis.

/// The label of a role in a meeting.
String participantRoleLabel(AppLocalizations l10n, ParticipantRole role) =>
    switch (role) {
      ParticipantRole.chair => l10n.meetingsParticipantRoleChair,
      ParticipantRole.secretary => l10n.meetingsParticipantRoleSecretary,
      ParticipantRole.member => l10n.meetingsParticipantRoleMember,
      ParticipantRole.guest => l10n.meetingsParticipantRoleGuest,
    };

/// The badge of a resolution: where voting stands, not the raw status.
String votingStateLabel(AppLocalizations l10n, VotingState state) =>
    switch (state) {
      VotingState.open => l10n.meetingsVotingStateOpen,
      VotingState.closed => l10n.meetingsVotingStateClosed,
      VotingState.windowOver => l10n.meetingsVotingStateWindowOver,
    };

/// The line that dates the voting of a resolution: a deadline while it is
/// open, the date it closed on otherwise. The wording is neutral: it is true
/// whether the date is ahead or behind. [date] is already formatted.
String votingDateLabel(AppLocalizations l10n, VotingState state, String date) =>
    switch (state) {
      VotingState.open => l10n.meetingsMeetingVotingDeadline(date),
      VotingState.closed ||
      VotingState.windowOver => l10n.meetingsMeetingVotingClosedOn(date),
    };

/// The label of a confidentiality level.
String confidentialityLabel(
  AppLocalizations l10n,
  ConfidentialityLevel level,
) => switch (level) {
  ConfidentialityLevel.public => l10n.meetingsConfidentialityPublic,
  ConfidentialityLevel.internal => l10n.meetingsConfidentialityInternal,
  ConfidentialityLevel.confidential => l10n.meetingsConfidentialityConfidential,
};

/// The label of a choice of vote.
String voteChoiceLabel(AppLocalizations l10n, VoteChoice choice) =>
    switch (choice) {
      VoteChoice.forChoice => l10n.votesVoteChoiceFor,
      VoteChoice.against => l10n.votesVoteChoiceAgainst,
      VoteChoice.abstain => l10n.votesVoteChoiceAbstain,
    };

/// The label of an option of the period control.
String meetingPeriodLabel(AppLocalizations l10n, MeetingPeriod period) =>
    switch (period) {
      MeetingPeriod.upcoming => l10n.meetingsPeriodUpcoming,
      MeetingPeriod.past => l10n.meetingsPeriodPast,
    };

/// The text shown for an empty list of each period.
String emptyListLabel(AppLocalizations l10n, MeetingPeriod period) =>
    switch (period) {
      MeetingPeriod.upcoming => l10n.meetingsEmptyUpcoming,
      MeetingPeriod.past => l10n.meetingsEmptyPast,
    };

/// The colour of the badge of a confidentiality level.
BadgeTone confidentialityTone(ConfidentialityLevel level) => switch (level) {
  ConfidentialityLevel.public ||
  ConfidentialityLevel.internal => BadgeTone.neutral,
  ConfidentialityLevel.confidential => BadgeTone.confidential,
};

/// The colour of the badge of a voting state.
BadgeTone votingStateTone(VotingState state) => switch (state) {
  VotingState.open => BadgeTone.positive,
  VotingState.closed || VotingState.windowOver => BadgeTone.neutral,
};
