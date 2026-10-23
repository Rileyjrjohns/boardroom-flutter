import 'package:flutter/widgets.dart';

/// The actions in the header of the meetings list (docs/spec/screens.md "Header
/// actions"): the pending votes, with a count when there are some, and signing
/// out, which asks for a confirmation first.
///
/// A placeholder until the votes and auth pieces it stands on exist: it reads
/// the count from the pending votes provider of the votes feature
/// (`pendingVotesProvider`) and opens the `SignOutDialog` of the auth feature
/// with the number of pending votes. The final integration step writes it, with
/// `AuthTestIds.signOutButton`, `VotesTestIds.pendingVotesButton` and
/// `VotesTestIds.pendingVotesBadge`, and `openPendingVotes(context)` from
/// `lib/core/presentation/navigation/navigate.dart`.
class HeaderActions extends StatelessWidget {
  /// Creates the actions.
  const new({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
