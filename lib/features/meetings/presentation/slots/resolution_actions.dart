import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a feature adds under a resolution of a meeting. Voting is the case: a
/// resolution is the business of the meetings, what the user can do about it
/// (cast a vote, see it wait to be sent) is the business of the votes. The
/// meetings declare this slot, the votes implement it, and the composition
/// (`lib/app/providers/slot_overrides.dart`) plugs the one into the other: the
/// meetings never import the votes.
///
/// The widget it builds is shown under the card of the [resolution], in the
/// place of the line that tells the vote the server recorded.
typedef ResolutionActionsBuilder = Widget Function(
  BuildContext context, {
  required Meeting meeting,
  required Resolution resolution,
});

/// The slot of the resolution actions. Nothing under a resolution until a
/// feature fills it: the meeting is then display only, and tells the vote the
/// server recorded.
final resolutionActionsProvider = Provider<ResolutionActionsBuilder?>(
  (ref) => null,
);
