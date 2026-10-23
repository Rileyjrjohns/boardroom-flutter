import 'dart:async';

import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/votes/application/use_cases/sync_pending_votes.dart';
import 'package:boardroom/features/votes/presentation/providers.dart';
import 'package:boardroom/features/votes/presentation/state/pending_votes.dart';
import 'package:boardroom/features/votes/presentation/state/refresh_meetings.dart';
import 'package:boardroom/features/votes/presentation/state/sync_summary.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'vote_sync.g.dart';

/// Asks for a synchronisation of the votes that wait in the outbox.
typedef RequestVoteSync = void Function();

/// The one place that decides when the votes waiting in the outbox are sent
/// (the `useVoteSync` of the React Native app). The shell calls the function it
/// gives when something happened that may allow it: the connection came back,
/// the app returned to the foreground (after the lock and the session are
/// settled), the user signed in or unlocked. The application layer does not
/// watch anything by itself; this is the trigger.
///
/// - Never while the app is locked or nobody is signed in: the request is
///   dropped (the unlock or the sign-in asks again), and the use case would
///   refuse anyway.
/// - Never two runs at once from the interface: a request that comes while a
///   run is under way is remembered and answered with one more run when it
///   ends, so that a vote queued meanwhile, or a connection that came back
///   meanwhile, is not forgotten. (The use case also refuses a second run on
///   its own instance; this is what keeps the interface from asking.)
/// - A result is told only when something was sent or rejected, in the banner
///   of the screen, added to what earlier runs told until the user dismisses
///   it, and then the queries it changes are refreshed: the outbox and the
///   meetings, whose resolutions carry the votes the server has recorded.
/// - A run that meets the end of the session (the server refused it, it
///   expired, the app locked meanwhile) ends it for the whole app, exactly like
///   a query would.
/// - A run answers for the access it started under (the epoch of the access):
///   if the user left and somebody else came while it was under way, its answer
///   is dropped, whatever it says, and the request that came meanwhile is
///   answered with a run of its own.
@Riverpod(keepAlive: true)
RequestVoteSync requestVoteSync(Ref ref) {
  var running = false;
  var requestedAgain = false;

  bool unlocked() => ref.mounted && ref.read(accessProvider) == Access.unlocked;

  Future<void> runOnce() async {
    // The run belongs to the access it started under: if the user left
    // meanwhile, and somebody else came, what it found is neither theirs to
    // read nor a reason to end their session.
    final epoch = ref.read(accessControllerProvider).epoch;
    final result = await ref.read(syncPendingVotesUseCaseProvider).execute();
    if (!ref.mounted || ref.read(accessControllerProvider).epoch != epoch) {
      return;
    }
    final SyncReport report;
    switch (result) {
      case Err(:final error):
        // The handler ends the session only for a code that ends it.
        ref.read(sessionEndHandlerProvider)(error.code, epoch);
        return;
      case Ok(:final value):
        report = value;
    }

    final int synced;
    final int rejected;
    switch (report) {
      case SyncAlreadyRunning():
        return;
      case SyncCompleted():
        synced = report.synced.length;
        rejected = report.rejected.length;
      case SyncInterrupted(:final interruptedBy):
        ref.read(sessionEndHandlerProvider)(interruptedBy.code, epoch);
        synced = report.synced.length;
        rejected = report.rejected.length;
    }
    if (synced == 0 && rejected == 0) {
      return;
    }
    ref
        .read(syncSummaryStateProvider.notifier)
        .show(SyncSummary(synced: synced, rejected: rejected), epoch);
    await Future.wait([refreshPendingVotes(ref), refreshMeetings(ref)]);
  }

  Future<void> drain() async {
    try {
      do {
        requestedAgain = false;
        await runOnce();
      } while (requestedAgain && unlocked());
    } finally {
      running = false;
    }
  }

  return () {
    if (!unlocked()) {
      return;
    }
    if (running) {
      requestedAgain = true;
      return;
    }
    running = true;
    unawaited(drain());
  };
}
