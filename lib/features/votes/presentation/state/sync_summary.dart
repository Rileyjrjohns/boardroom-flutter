import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sync_summary.g.dart';

/// What a run of the synchronisation did that is worth telling the user.
@immutable
final class SyncSummary {
  /// Creates a summary of [synced] votes sent and [rejected] votes refused.
  const new({required this.synced, required this.rejected});

  /// How many votes were sent.
  final int synced;

  /// How many votes were refused.
  final int rejected;

  @override
  bool operator ==(Object other) =>
      other is SyncSummary &&
      other.synced == synced &&
      other.rejected == rejected;

  @override
  int get hashCode => Object.hash(synced, rejected);
}

/// What the synchronisations sent or rejected, added up until the user
/// dismisses it, so that a later run does not wipe what an earlier one told. A
/// result that has to outlive the screen that happened to be showing when it
/// came. It belongs to the session: it is forgotten when the user leaves the
/// open app (the epoch of the access moves), and a result for another epoch is
/// dropped. It never holds the choice of a vote: a report names resolutions and
/// counts only.
@Riverpod(keepAlive: true)
class SyncSummaryState extends _$SyncSummaryState {
  @override
  SyncSummary? build() {
    // Whatever the session left to tell is forgotten as soon as the user leaves
    // the open app, the same moment their access changes.
    ref.listen(accessControllerProvider, (previous, next) {
      if (previous != null && previous.epoch != next.epoch) {
        state = null;
      }
    });
    return null;
  }

  /// Adds what a run sent or rejected to the summary being shown, for the epoch
  /// the run started under, while the app is open. A result for another epoch
  /// is dropped.
  void show(SyncSummary summary, int epoch) {
    final access = ref.read(accessControllerProvider);
    // A result that comes after the user left the open app, or for the user
    // before them, is not theirs to read.
    if (access.access != Access.unlocked || access.epoch != epoch) {
      return;
    }
    final shown = state;
    state = SyncSummary(
      synced: (shown?.synced ?? 0) + summary.synced,
      rejected: (shown?.rejected ?? 0) + summary.rejected,
    );
  }

  /// The user closed the summary.
  void dismiss() => state = null;
}
