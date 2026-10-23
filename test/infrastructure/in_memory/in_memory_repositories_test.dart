import '../../application/support/contracts/document_repository_contract.dart';
import '../../application/support/contracts/meeting_repository_contract.dart';
import '../../application/support/contracts/vote_repository_contract.dart';
import '../../domain/support/builders.dart';
import '../support/server_setups.dart';
import '../support/test_server.dart';

// The three repositories are windows on one simulated server. Each runs the
// contract suite of its port, with the server prepared the way the suite asks.

void main() {
  describeMeetingRepositoryContract('InMemoryMeetingRepository', () {
    final server = createTestServer();
    final setup = meetingsServerSide(server);
    return MeetingRepositoryHarness(
      repository: server.meetings,
      now: server.clock.now(),
      serve: setup.serve,
      forbid: setup.forbid,
      recordVote: setup.recordVote,
      signInAs: (userId) {
        server.auth.openSessionFor(aUser(id: userId));
      },
      setOnline: server.network.setOnline,
      refuseCaller: () async {
        await server.auth.signOut();
      },
    );
  }, const MeetingRepositoryContractOptions(projectsRecordedVotes: true));

  describeDocumentRepositoryContract('InMemoryDocumentRepository', () {
    final server = createTestServer();
    final setup = documentsServerSide(server);
    return DocumentRepositoryHarness(
      repository: server.documents,
      serve: setup.serve,
      forbid: setup.forbid,
      signInAs: (userId) {
        server.auth.openSessionFor(aUser(id: userId));
      },
      setOnline: server.network.setOnline,
      refuseCaller: () async {
        await server.auth.signOut();
      },
    );
  }, const DocumentRepositoryContractOptions(downloadsPerUserAndVersion: true));

  describeVoteRepositoryContract('InMemoryVoteRepository', () {
    final server = createTestServer();
    final setup = votesServerSide(server);
    return VoteRepositoryHarness(
      repository: server.votes,
      now: server.clock.now(),
      setOnline: server.network.setOnline,
      signOut: () async {
        await server.auth.signOut();
      },
      authenticateAs: (userId) {
        server.auth.openSessionFor(aUser(id: userId));
      },
      serve: setup.serve,
      change: setup.change,
      advanceClock: server.clock.advance,
      recordedCount: setup.recordedCount,
    );
  }, const VoteRepositoryContractOptions(enforcesBusinessRules: true));
}
