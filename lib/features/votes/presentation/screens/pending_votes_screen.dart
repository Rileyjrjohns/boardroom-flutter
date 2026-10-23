import 'package:boardroom/features/votes/presentation/test_ids.dart';
import 'package:flutter/widgets.dart';

/// The pending and rejected votes (docs/spec/screens.md "Pending votes").
///
/// A placeholder until the votes agent writes the screen: the router mounts
/// this class with this constructor, so the file is replaced in place.
class PendingVotesScreen extends StatelessWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: Key(VotesTestIds.pendingVotesScreen));
}
