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
/// THIS IS A PLACEHOLDER that does nothing: the votes agent replaces the body
/// (same name, same type) with the rules of `useVoteSync.ts`: never while the
/// access is not unlocked, never two runs at once (a request during a run is
/// remembered and answered with one more run), tell a result only when
/// something was sent or rejected (the sync summary), refresh the outbox and
/// the meetings afterwards, end the session on a session-ending code, and drop
/// the answer of a run whose epoch is no longer current.
@Riverpod(keepAlive: true)
RequestVoteSync requestVoteSync(Ref ref) => () {};
