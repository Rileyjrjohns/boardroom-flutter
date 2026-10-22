import 'package:boardroom/application/shared/app_lock.dart';
import 'package:boardroom/application/shared/end_session.dart';
import 'package:boardroom/application/shared/load_meeting.dart';
import 'package:boardroom/application/shared/load_with_cache_fallback.dart';
import 'package:boardroom/application/shared/purge_caches.dart';
import 'package:boardroom/application/shared/require_session.dart';
import 'package:boardroom/application/shared/screen_protection_coordinator.dart';
import 'package:boardroom/application/use_cases/auth/unlock_app.dart';
import 'package:boardroom/application/use_cases/connectivity/observe_connectivity.dart';
import 'package:boardroom/application/use_cases/documents/close_document.dart';
import 'package:boardroom/application/use_cases/documents/observe_screen_capture.dart';
import 'package:boardroom/application/use_cases/documents/open_document.dart';
import 'package:boardroom/application/use_cases/meetings/list_meetings.dart';
import 'package:boardroom/application/use_cases/votes/acknowledge_rejected_vote.dart';
import 'package:boardroom/application/use_cases/votes/cast_vote.dart';
import 'package:boardroom/application/use_cases/votes/discard_unreadable_votes.dart';
import 'package:boardroom/application/use_cases/votes/list_pending_votes.dart';
import 'package:boardroom/application/use_cases/votes/sync_pending_votes.dart';
import 'package:boardroom/domain/value_objects/duration.dart';

import '../../domain/support/builders.dart';
import 'fake_auth_session.dart';
import 'fake_biometric_gate.dart';
import 'fake_clock.dart';
import 'fake_connectivity.dart';
import 'fake_document_cache.dart';
import 'fake_document_repository.dart';
import 'fake_meeting_cache.dart';
import 'fake_meeting_repository.dart';
import 'fake_monitoring.dart';
import 'fake_network.dart';
import 'fake_screen_protection.dart';
import 'fake_vote_outbox.dart';
import 'fake_vote_repository.dart';
import 'screen_protection_deps.dart';

/// One fake of every port, wired together: the remote fakes share [network].
/// The property names are those of the `deps` objects of the use cases, so the
/// whole set can be passed to any of them: `CastVote(createFakes())`. The user
/// is signed in, the network is up, the clock stands at `now`, the app is
/// unlocked, the biometrics succeed and the screen protection is available. It
/// also carries the values of the configuration the use cases take in their
/// deps: [maxCacheAge] (7 days) and [maxAttempts] (5).
///
/// It implements the deps of the shared helpers of the application, and later
/// those of the use cases: that is what lets a test pass it where TypeScript
/// passes the object literal. [copyWith] is the spread with an override
/// (`fakes.copyWith(appLock: AppLock())`).
final class Fakes
    implements
        PurgeCachesDeps,
        EndSessionDeps,
        RequireSessionDeps,
        CacheFallbackDeps,
        LoadMeetingDeps,
        ScreenProtectionCoordinatorDeps,
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
  /// Creates the set. Use [createFakes].
  new _({
    required this.network,
    required this.clock,
    required this.appLock,
    required this.monitoring,
    required this.auth,
    required this.biometricGate,
    required this.connectivity,
    required this.screenProtection,
    required this.screenProtectionCoordinator,
    required this.maxCacheAge,
    required this.maxAttempts,
    required this.meetings,
    required this.meetingCache,
    required this.documents,
    required this.documentCache,
    required this.votes,
    required this.outbox,
  });

  /// The connectivity switch of the remote fakes.
  final FakeNetwork network;

  /// The clock, standing at `now`.
  @override
  final FakeClock clock;

  /// The lock of the app, unlocked.
  @override
  final AppLock appLock;

  /// What the use cases logged and reported.
  @override
  final FakeMonitoring monitoring;

  /// The sign-in and the stored session.
  @override
  final FakeAuthSession auth;

  /// The biometrics of the device.
  @override
  final FakeBiometricGate biometricGate;

  /// The connectivity status of the device.
  @override
  final FakeConnectivity connectivity;

  /// The screen protection of the device.
  @override
  final FakeScreenProtection screenProtection;

  /// Opens and closes the screen protection for the documents on display,
  /// over [screenProtection].
  @override
  final ScreenProtectionCoordinator screenProtectionCoordinator;

  /// How old a cached copy may be (7 days).
  @override
  final DurationMillis maxCacheAge;

  /// How many failed attempts a vote may have (5).
  @override
  final int maxAttempts;

  /// The remote meetings.
  @override
  final FakeMeetingRepository meetings;

  /// The local cache of meetings.
  @override
  final FakeMeetingCache meetingCache;

  /// The remote documents.
  @override
  final FakeDocumentRepository documents;

  /// The local cache of documents.
  @override
  final FakeDocumentCache documentCache;

  /// The server that records votes.
  @override
  final FakeVoteRepository votes;

  /// The local queue of votes.
  @override
  final FakeVoteOutbox outbox;

  /// The same fakes, with some values replaced: a lock of the app of its own,
  /// another maximum age, another number of attempts. The fakes themselves are
  /// shared with the copy, not duplicated, as in a spread.
  Fakes copyWith({
    AppLock? appLock,
    DurationMillis? maxCacheAge,
    int? maxAttempts,
  }) => Fakes._(
    network: network,
    clock: clock,
    appLock: appLock ?? this.appLock,
    monitoring: monitoring,
    auth: auth,
    biometricGate: biometricGate,
    connectivity: connectivity,
    screenProtection: screenProtection,
    screenProtectionCoordinator: screenProtectionCoordinator,
    maxCacheAge: maxCacheAge ?? this.maxCacheAge,
    maxAttempts: maxAttempts ?? this.maxAttempts,
    meetings: meetings,
    meetingCache: meetingCache,
    documents: documents,
    documentCache: documentCache,
    votes: votes,
    outbox: outbox,
  );
}

/// Builds the set of fakes of a test.
Fakes createFakes() {
  final network = FakeNetwork();
  final auth = FakeAuthSession();
  final screenProtection = FakeScreenProtection();
  return Fakes._(
    network: network,
    clock: FakeClock(),
    appLock: AppLock(locked: false),
    monitoring: FakeMonitoring(),
    auth: auth,
    biometricGate: FakeBiometricGate(),
    connectivity: FakeConnectivity(),
    screenProtection: screenProtection,
    screenProtectionCoordinator: ScreenProtectionCoordinator(
      ScreenProtectionDeps(screenProtection),
    ),
    maxCacheAge: aDuration(7 * millisPerDay),
    maxAttempts: 5,
    meetings: FakeMeetingRepository(network),
    meetingCache: FakeMeetingCache(),
    documents: FakeDocumentRepository(network),
    documentCache: FakeDocumentCache(),
    votes: FakeVoteRepository(network, auth),
    outbox: FakeVoteOutbox(),
  );
}
