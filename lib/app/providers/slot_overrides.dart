import 'package:flutter_riverpod/misc.dart' show Override;

/// The links between features that no feature may make, plugged in the root
/// container (the two `Provider`s of the `AppProviders` of the React Native
/// app):
///
/// - the banner of the screens tells what the votes synchronised: the core
///   declares `bannerNoticesProvider`, the votes implement `BannerNotices` (the
///   sync summary), and the override goes here;
/// - a resolution of a meeting offers the vote: the meetings declare the slot
///   (`resolutionActionsSlotProvider` in
///   `features/meetings/presentation/slots/resolution_actions.dart`), the votes
///   implement it, and the override goes here.
///
/// It is empty until the votes agent has written both implementations: add
/// `bannerNoticesProvider.overrideWithValue(syncSummaryNotices)` and the slot
/// override, and keep the order.
List<Override> slotOverrides() => const [];
