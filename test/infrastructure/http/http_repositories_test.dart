import '../../application/support/contracts/auth_session_contract.dart';
import '../../application/support/contracts/document_repository_contract.dart';
import '../../application/support/contracts/meeting_repository_contract.dart';
import '../../application/support/contracts/vote_repository_contract.dart';
import '../../domain/support/builders.dart';
import '../support/http_adapters_world.dart';
import '../support/http_world.dart';
import '../support/server_setups.dart';
import '../support/test_server.dart';

// The HTTP adapters run the same contract suites as the fakes and the in-memory
// adapters. The server behind them is the simulated one, reached through the
// routes of the API (`MockApi`) and the dio adapter that stands in for the
// network, so a request goes through the real client, the real wire classes and
// the real mappers, and is answered by the same rules as the in-memory
// repositories.

void main() {
  final installed = installFixtureServer();

  /// A device that has no connection: its requests fail the way a request
  /// without a network does.
  void setOnline({required bool online}) {
    installed.conditions.online = online;
  }

  describeMeetingRepositoryContract('HttpMeetingRepository', () async {
    final world = createHttpWorld(installed);
    await world.signInAs(aUserId());
    final setup = meetingsServerSide(world.serverSide.server);
    return MeetingRepositoryHarness(
      repository: world.meetings,
      now: world.clock.now(),
      serve: setup.serve,
      forbid: setup.forbid,
      recordVote: setup.recordVote,
      signInAs: world.signInAs,
      setOnline: setOnline,
      refuseCaller: world.api.revokeSessions,
    );
  }, const MeetingRepositoryContractOptions(projectsRecordedVotes: true));

  describeDocumentRepositoryContract('HttpDocumentRepository', () async {
    final world = createHttpWorld(installed);
    await world.signInAs(aUserId());
    final setup = documentsServerSide(world.serverSide.server);
    return DocumentRepositoryHarness(
      repository: world.documents,
      serve: setup.serve,
      forbid: setup.forbid,
      signInAs: world.signInAs,
      setOnline: setOnline,
      refuseCaller: world.api.revokeSessions,
    );
  }, const DocumentRepositoryContractOptions(downloadsPerUserAndVersion: true));

  describeVoteRepositoryContract('HttpVoteRepository', () async {
    final world = createHttpWorld(installed);
    await world.signInAs(aUserId());
    final setup = votesServerSide(world.serverSide.server);
    return VoteRepositoryHarness(
      repository: world.votes,
      now: world.clock.now(),
      setOnline: setOnline,
      signOut: () async {
        await world.auth.signOut();
      },
      authenticateAs: world.signInAs,
      serve: setup.serve,
      change: setup.change,
      advanceClock: world.clock.advance,
      recordedCount: setup.recordedCount,
    );
  }, const VoteRepositoryContractOptions(enforcesBusinessRules: true));

  describeAuthSessionContract('HttpAuthSession', () {
    final world = createHttpWorld(installed);
    final [alice, bruno, ...] = world.accounts;
    return AuthSessionHarness(
      auth: world.auth,
      accounts: (
        AuthSessionAccount(credentials: credentialsOf(alice), user: alice.user),
        AuthSessionAccount(credentials: credentialsOf(bruno), user: bruno.user),
      ),
      now: world.clock.now,
      advanceClock: world.clock.advance,
      setOnline: setOnline,
    );
  });
}
