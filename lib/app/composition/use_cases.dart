import 'package:boardroom/app/composition/meeting_cache_vote_recorder.dart';
import 'package:boardroom/app/composition/ports.dart';
import 'package:boardroom/app/composition/session_data_purgers.dart'
    as composition;
import 'package:boardroom/core/application/offline/load_with_cache_fallback.dart';
import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/session_gate.dart';
import 'package:boardroom/core/application/use_cases/observe_connectivity.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/features/auth/application/ports/auth_session.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/application/ports/session_data_purger.dart';
import 'package:boardroom/features/auth/application/session/app_lock.dart';
import 'package:boardroom/features/auth/application/session/auth_session_gate.dart';
import 'package:boardroom/features/auth/application/session/end_session.dart';
import 'package:boardroom/features/auth/application/session/purge_caches.dart';
import 'package:boardroom/features/auth/application/session/require_session.dart';
import 'package:boardroom/features/auth/application/use_cases/evaluate_app_lock.dart';
import 'package:boardroom/features/auth/application/use_cases/get_current_user.dart';
import 'package:boardroom/features/auth/application/use_cases/restore_session.dart';
import 'package:boardroom/features/auth/application/use_cases/sign_in.dart';
import 'package:boardroom/features/auth/application/use_cases/sign_out.dart';
import 'package:boardroom/features/auth/application/use_cases/unlock_app.dart';
import 'package:boardroom/features/documents/application/document_cache_evictor.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:boardroom/features/documents/application/ports/document_repository.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/application/screen_protection_coordinator.dart';
import 'package:boardroom/features/documents/application/use_cases/close_document.dart';
import 'package:boardroom/features/documents/application/use_cases/observe_screen_capture.dart';
import 'package:boardroom/features/documents/application/use_cases/open_document.dart';
import 'package:boardroom/features/meetings/application/load_meeting.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_document_evictor.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_repository.dart';
import 'package:boardroom/features/meetings/application/use_cases/get_meeting.dart';
import 'package:boardroom/features/meetings/application/use_cases/list_meetings.dart';
import 'package:boardroom/features/votes/application/ports/recorded_vote_sink.dart';
import 'package:boardroom/features/votes/application/ports/vote_outbox.dart';
import 'package:boardroom/features/votes/application/ports/vote_repository.dart';
import 'package:boardroom/features/votes/application/use_cases/acknowledge_rejected_vote.dart';
import 'package:boardroom/features/votes/application/use_cases/cast_vote.dart';
import 'package:boardroom/features/votes/application/use_cases/discard_unreadable_votes.dart';
import 'package:boardroom/features/votes/application/use_cases/list_pending_votes.dart';
import 'package:boardroom/features/votes/application/use_cases/sync_pending_votes.dart';
import 'package:meta/meta.dart';

/// Every use case of the application, built once and shared.
@immutable
final class UseCases {
  /// Creates the set. Use [wireUseCases].
  const new({
    required this.signIn,
    required this.signOut,
    required this.restoreSession,
    required this.getCurrentUser,
    required this.evaluateAppLock,
    required this.unlockApp,
    required this.listMeetings,
    required this.getMeeting,
    required this.openDocument,
    required this.closeDocument,
    required this.observeScreenCapture,
    required this.observeConnectivity,
    required this.castVote,
    required this.syncPendingVotes,
    required this.listPendingVotes,
    required this.acknowledgeRejectedVote,
    required this.discardUnreadableVotes,
  });

  /// Signs a user in with their credentials.
  final SignIn signIn;

  /// Ends the session and empties what it left on the device.
  final SignOut signOut;

  /// Reads the stored session at the start and locks the app.
  final RestoreSession restoreSession;

  /// Tells who is signed in, as a check of the session.
  final GetCurrentUser getCurrentUser;

  /// Decides whether the app locks after a stay in the background.
  final EvaluateAppLock evaluateAppLock;

  /// Unlocks the app with the biometrics.
  final UnlockApp unlockApp;

  /// Lists a page of upcoming or past meetings.
  final ListMeetings listMeetings;

  /// Reads one meeting.
  final GetMeeting getMeeting;

  /// Opens a document and protects the screen when it is confidential.
  final OpenDocument openDocument;

  /// Closes a document and lifts the protection when no view needs it.
  final CloseDocument closeDocument;

  /// Tells when the screen is captured.
  final ObserveScreenCapture observeScreenCapture;

  /// Tells the connectivity of the device and its changes.
  final ObserveConnectivity observeConnectivity;

  /// Casts a vote, or queues it when the server cannot be reached.
  final CastVote castVote;

  /// Sends the queued votes.
  final SyncPendingVotes syncPendingVotes;

  /// Lists the votes in the queue.
  final ListPendingVotes listPendingVotes;

  /// Lets the user acknowledge a vote the server refused.
  final AcknowledgeRejectedVote acknowledgeRejectedVote;

  /// Drops the queued votes that can no longer be read.
  final DiscardUnreadableVotes discardUnreadableVotes;
}

/// The deps of every use case, in one object over the [Ports] and the
/// [UseCaseSettings]: the idea of the `Fakes` of the tests, over real ports.
/// The objects that hold something in memory are made here, once, and handed
/// out by every getter (see [wireUseCases]).
final class _Deps
    implements
        PurgeCachesDeps,
        EndSessionDeps,
        RequireSessionDeps,
        CacheFallbackDeps,
        LoadMeetingDeps,
        ScreenProtectionCoordinatorDeps,
        EvaluateAppLockDeps,
        UnlockAppDeps,
        ObserveConnectivityDeps,
        CloseDocumentDeps,
        ObserveScreenCaptureDeps,
        OpenDocumentDeps,
        ListMeetingsDeps,
        AcknowledgeRejectedVoteDeps,
        CastVoteDeps,
        DiscardUnreadableVotesDeps,
        ListPendingVotesDeps,
        SyncPendingVotesDeps {
  new(this._ports, UseCaseSettings settings)
    : maxCacheAge = settings.maxCacheAge,
      maxAttempts = settings.maxAttempts,
      gracePeriod = settings.gracePeriod,
      appLock = AppLock(locked: settings.startsLocked),
      screenProtectionCoordinator = ScreenProtectionCoordinator(
        _ScreenProtectionOnly(_ports.screenProtection),
      );

  final Ports _ports;

  @override
  final DurationMillis maxCacheAge;

  @override
  final int maxAttempts;

  @override
  final DurationMillis gracePeriod;

  @override
  final AppLock appLock;

  @override
  final ScreenProtectionCoordinator screenProtectionCoordinator;

  @override
  Clock get clock => _ports.clock;

  @override
  Monitoring get monitoring => _ports.monitoring;

  @override
  AuthSession get auth => _ports.auth;

  @override
  BiometricGate get biometricGate => _ports.biometricGate;

  @override
  Connectivity get connectivity => _ports.connectivity;

  @override
  ScreenProtection get screenProtection => _ports.screenProtection;

  @override
  MeetingRepository get meetings => _ports.meetings;

  @override
  MeetingCache get meetingCache => _ports.meetingCache;

  @override
  DocumentRepository get documents => _ports.documents;

  @override
  DocumentCache get documentCache => _ports.documentCache;

  @override
  VoteRepository get votes => _ports.votes;

  @override
  VoteOutbox get outbox => _ports.outbox;

  /// What the offline policy needs of the session is the gate of `auth`,
  /// handed over as a port of the core.
  @override
  SessionGate get sessionGate => AuthSessionGate(this);

  /// What a session leaves on the device, as the composition lists it: the
  /// meeting cache, then the document cache.
  @override
  List<SessionDataPurger> get sessionDataPurgers =>
      composition.sessionDataPurgers(
        meetingCache: meetingCache,
        documentCache: documentCache,
      );

  /// A vote the server recorded is written into the cached meeting by the glue
  /// between the votes and the meetings.
  @override
  RecordedVoteSink get recordedVoteSink =>
      MeetingCacheVoteRecorder(meetingCache: meetingCache, session: this);

  /// The documents of a refused meeting are dropped through the port of the
  /// meetings, which the documents implement.
  @override
  MeetingDocumentEvictor get documentEvictor =>
      DocumentCacheEvictor(documentCache);
}

/// The deps of the coordinator of the screen protection: the switch and
/// nothing else.
final class _ScreenProtectionOnly implements ScreenProtectionCoordinatorDeps {
  const new(this.screenProtection);

  @override
  final ScreenProtection screenProtection;
}

/// The wiring: manual constructor injection, typed end to end. Each use case is
/// handed the ports it names in its deps, plus the configuration values it
/// takes. No container library, no lookup by name, no global instance: a call
/// builds a whole new set.
///
/// Three objects hold something in memory, and must therefore exist once for
/// the whole app:
///
/// - `AppLock` says whether the app is locked. Every use case that reads,
///   queues or sends something for the user asks it through the session guard,
///   and `RestoreSession`, `EvaluateAppLock`, `UnlockApp`, `SignIn` and
///   `SignOut` change it. Two instances would each be unlocked on their own,
///   and the lock would guard nothing.
/// - `ScreenProtectionCoordinator` counts the views of the documents that are
///   open and queues the calls to the platform. `OpenDocument` and
///   `CloseDocument` share the one built here; two coordinators would each
///   switch the protection off on their own say-so.
/// - `CastVote` refuses a second vote on a resolution being cast, and
///   `SyncPendingVotes` refuses a second run while one is in progress. A second
///   instance of either has no memory of the first.
///
/// Every screen gets them from the returned object, which is built once by the
/// app.
UseCases wireUseCases(Ports ports, UseCaseSettings settings) {
  final deps = _Deps(ports, settings);
  return UseCases(
    signIn: SignIn(deps),
    signOut: SignOut(deps),
    restoreSession: RestoreSession(deps),
    getCurrentUser: GetCurrentUser(deps),
    evaluateAppLock: EvaluateAppLock(deps),
    unlockApp: UnlockApp(deps),
    listMeetings: ListMeetings(deps),
    getMeeting: GetMeeting(deps),
    openDocument: OpenDocument(deps),
    closeDocument: CloseDocument(deps),
    observeScreenCapture: ObserveScreenCapture(deps),
    observeConnectivity: ObserveConnectivity(deps),
    castVote: CastVote(deps),
    syncPendingVotes: SyncPendingVotes(deps),
    listPendingVotes: ListPendingVotes(deps),
    acknowledgeRejectedVote: AcknowledgeRejectedVote(deps),
    discardUnreadableVotes: DiscardUnreadableVotes(deps),
  );
}
