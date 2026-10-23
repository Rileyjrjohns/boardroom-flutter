import 'package:boardroom/core/presentation/components/status_banner.dart';
import 'package:boardroom/features/meetings/presentation/slots/resolution_actions.dart';
import 'package:boardroom/features/votes/presentation/components/sync_summary_notice.dart';
import 'package:boardroom/features/votes/presentation/slots/vote_resolution_actions.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The links between features that no feature may make, plugged in the root
/// container (the two `Provider`s of the `AppProviders` of the React Native
/// app):
///
/// - the banner of the screens tells what the votes synchronised: the core
///   declares `bannerNoticesProvider`, the votes implement `BannerNotices` (the
///   sync summary), and the override goes here;
/// - a resolution of a meeting offers the vote: the meetings declare the slot
///   (`resolutionActionsProvider` in
///   `features/meetings/presentation/slots/resolution_actions.dart`), the votes
///   implement it (`voteResolutionActions`), and the override goes here.
List<Override> slotOverrides() => [
  bannerNoticesProvider.overrideWithValue(syncSummaryNotices),
  resolutionActionsProvider.overrideWithValue(voteResolutionActions),
];
