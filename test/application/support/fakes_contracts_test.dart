import 'package:boardroom/domain/entities/document.dart';
import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/value_objects/credentials.dart';
import 'package:boardroom/domain/value_objects/document_location.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/meeting_period.dart';

import '../../domain/support/builders.dart';
import 'contracts/auth_session_contract.dart';
import 'contracts/connectivity_contract.dart';
import 'contracts/document_cache_contract.dart';
import 'contracts/document_repository_contract.dart';
import 'contracts/meeting_cache_contract.dart';
import 'contracts/meeting_repository_contract.dart';
import 'contracts/screen_protection_contract.dart';
import 'contracts/support.dart';
import 'contracts/vote_outbox_contract.dart';
import 'contracts/vote_repository_contract.dart';
import 'create_fakes.dart';
import 'fake_connectivity.dart';
import 'fake_document_cache.dart';
import 'fake_meeting_cache.dart';
import 'fake_screen_protection.dart';
import 'fake_vote_outbox.dart';

// The fakes stand in for the adapters in every use case test, so what they
// promise must match the contract written in the ports. The suites that check
// it are the ones the real adapters run too (test/application/support/contracts).

void main() {
  describeMeetingCacheContract('FakeMeetingCache', () {
    final cache = FakeMeetingCache();
    return MeetingCacheHarness(
      cache: cache,
      breakWrites: () {
        cache.writeFailure = storageWriteFailed();
      },
      repairWrites: () {
        cache.writeFailure = null;
      },
    );
  }, inMemoryStore);

  describeDocumentCacheContract(
    'FakeDocumentCache',
    () {
      final cache = FakeDocumentCache();
      return DocumentCacheHarness(
        cache: cache,
        breakWrites: () {
          cache.writeFailure = storageWriteFailed();
        },
        repairWrites: () {
          cache.writeFailure = null;
        },
      );
    },
    const DocumentCacheContractOptions(
      failsStatements: false,
      survivesReopen: false,
      keepsFiles: false,
    ),
  );

  describeVoteOutboxContract(
    'FakeVoteOutbox',
    () {
      final outbox = FakeVoteOutbox();
      return VoteOutboxHarness(
        outbox: outbox,
        plantUnreadable: (voter, key) {
          outbox.seedUnreadable(voter, key);
        },
      );
    },
    const VoteOutboxContractOptions(
      failsStatements: false,
      survivesReopen: false,
      holdsUnreadable: true,
    ),
  );

  describeMeetingRepositoryContract('FakeMeetingRepository', () {
    final fakes = createFakes();
    final now = fakes.clock.now();
    final served = <MeetingId>{};
    return MeetingRepositoryHarness(
      repository: fakes.meetings,
      now: now,
      serve: (meetings) {
        served
          ..forEach(fakes.meetings.removeMeeting)
          ..clear();
        final upcoming = <MeetingSummary>[];
        final past = <MeetingSummary>[];
        for (final meeting in meetings) {
          fakes.meetings.addMeeting(meeting);
          served.add(meeting.id);
          final summary = aMeetingSummary(
            id: meeting.id,
            title: meeting.title,
            scheduledAt: meeting.scheduledAt,
            location: meeting.location,
          );
          if (meeting.scheduledAt > now) {
            upcoming.add(summary);
          } else {
            past.add(summary);
          }
        }
        fakes.meetings
          ..setMeetings(MeetingPeriod.upcoming, upcoming)
          ..setMeetings(MeetingPeriod.past, past);
      },
      forbid: (meeting) {
        fakes.meetings
          ..addMeeting(meeting)
          ..forbid(meeting.id);
      },
      recordVote: (vote) {
        // The scripted server returns the meetings it was given: it cannot
        // project a vote.
      },
      signInAs: (userId) {
        fakes.auth.session = aSession(user: aUser(id: userId));
      },
      setOnline: ({required online}) {
        fakes.network.online = online;
      },
      refuseCaller: () {
        fakes.meetings.failure = unauthorized();
      },
    );
  }, const MeetingRepositoryContractOptions(projectsRecordedVotes: false));

  describeDocumentRepositoryContract(
    'FakeDocumentRepository',
    () {
      final fakes = createFakes();
      DocumentLocation location(Document document) =>
          aDocumentLocation('file:///documents/${document.id}.pdf');
      return DocumentRepositoryHarness(
        repository: fakes.documents,
        serve: (documents) {
          for (final document in documents) {
            fakes.documents.addDocument(document, location(document));
          }
        },
        forbid: (document) {
          fakes.documents
            ..addDocument(document, location(document))
            ..forbid(document.id);
        },
        signInAs: (userId) {
          fakes.auth.session = aSession(user: aUser(id: userId));
        },
        setOnline: ({required online}) {
          fakes.network.online = online;
        },
        refuseCaller: () {
          fakes.documents.failure = unauthorized();
        },
      );
    },
    // The locations of the fake are given by the test: it downloads nothing.
    const DocumentRepositoryContractOptions(downloadsPerUserAndVersion: false),
  );

  describeVoteRepositoryContract('FakeVoteRepository', () {
    final fakes = createFakes();
    return VoteRepositoryHarness(
      repository: fakes.votes,
      now: fakes.clock.now(),
      setOnline: ({required online}) {
        fakes.network.online = online;
      },
      signOut: () {
        fakes.auth.session = null;
      },
      authenticateAs: (userId) {
        fakes.auth.session = aSession(user: aUser(id: userId));
      },
      serve: (meeting) {
        // The scripted server holds no meeting.
      },
      change: (meeting) {
        // The scripted server holds no meeting.
      },
      advanceClock: fakes.clock.advance,
      recordedCount: (vote) => fakes.votes
          .recordedVotes()
          .where((held) => held.idempotencyKey == vote.idempotencyKey)
          .length,
    );
  }, const VoteRepositoryContractOptions(enforcesBusinessRules: false));

  describeAuthSessionContract('FakeAuthSession', () {
    final fakes = createFakes();
    fakes.auth.session = null;
    final alice = aUser();
    final bruno = aUser(
      id: aUserId('user-2'),
      fullName: 'Bruno Durand',
      email: anEmail('bruno@example.com'),
    );
    final accounts = (
      AuthSessionAccount(
        credentials: Credentials(email: alice.email, password: 'alice-secret'),
        user: alice,
      ),
      AuthSessionAccount(
        credentials: Credentials(email: bruno.email, password: 'bruno-secret'),
        user: bruno,
      ),
    );
    for (final AuthSessionAccount(:credentials, :user) in [
      accounts.$1,
      accounts.$2,
    ]) {
      fakes.auth.registerAccount(
        credentials.email,
        credentials.password,
        aSession(user: user),
      );
    }
    return AuthSessionHarness(
      auth: fakes.auth,
      accounts: accounts,
      now: fakes.clock.now,
      advanceClock: fakes.clock.advance,
      setOnline: ({required online}) {
        fakes.auth.signInFailure = online ? null : networkUnavailable();
      },
    );
  });

  describeScreenProtectionContract('FakeScreenProtection', () {
    final protection = FakeScreenProtection();
    return ScreenProtectionHarness(
      protection: protection,
      isEnabled: () => protection.enabled,
      emit: protection.emit,
    );
  });

  describeConnectivityContract('FakeConnectivity', () {
    final connectivity = FakeConnectivity();
    return ConnectivityHarness(
      connectivity: connectivity,
      report: connectivity.emit,
    );
  });
}
