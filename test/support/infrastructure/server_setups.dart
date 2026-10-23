import 'package:boardroom/app/dev/in_memory/in_memory_backend.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';

import '../builders/builders.dart';
import 'test_server.dart';

// Test support, not production code: how the contract suites of the remote
// repositories prepare the content of the simulated server. They are the same
// whether the repository reaches the server directly (the in-memory adapters)
// or over HTTP, so they live here once.

/// A meeting that the signed-in user (`user-1`) is not invited to.
Meeting _withoutTheUser(Meeting meeting) => meeting.copyWith(
  participants: [
    aParticipant(userId: aUserId('user-9'), fullName: 'Someone Else'),
  ],
);

/// What the set-ups use of a test server: load content, and read what it
/// recorded.
typedef SetupServer = TestServer;

/// What the harness of `MeetingRepository` asks of the server: the meetings and
/// the votes it holds.
final class MeetingsServerSide {
  /// Creates the set-up for the server.
  new(this._server);

  final SetupServer _server;
  List<Meeting> _served = [];
  List<Meeting> _refused = [];
  List<Vote> _recorded = [];

  void _load() => _server.load(
    ServerContent(
      meetings: [..._served, ..._refused],
      recordedVotes: _recorded,
    ),
  );

  /// Makes the server hold [meetings], which the user takes part in.
  void serve(List<Meeting> meetings) {
    _served = meetings;
    _load();
  }

  /// Adds a copy of [meeting] that the user is not invited to.
  void forbid(Meeting meeting) {
    _refused = [..._refused, _withoutTheUser(meeting)];
    _load();
  }

  /// Makes the server hold [vote] as recorded.
  void recordVote(Vote vote) {
    _recorded = [..._recorded, vote];
    _load();
  }
}

/// What the harness of `DocumentRepository` asks of the server: the documents
/// it holds.
final class DocumentsServerSide {
  /// Creates the set-up for the server.
  new(this._server);

  final SetupServer _server;
  List<Document> _served = [];
  List<Document> _refused = [];

  void _load() => _server.load(
    ServerContent(
      meetings: [
        aMeeting(documents: _served),
        for (final document in _refused)
          _withoutTheUser(
            aMeeting(
              summary: aMeetingSummary(
                id: aMeetingId('refused-${document.id}'),
              ),
              agenda: [],
              documents: [document],
            ),
          ),
      ],
      recordedVotes: const [],
    ),
  );

  /// Makes the server hold [documents], which the user may have.
  void serve(List<Document> documents) {
    _served = documents;
    _load();
  }

  /// Adds [document], which the user may not have.
  void forbid(Document document) {
    _refused = [..._refused, document];
    _load();
  }
}

/// What the harness of `VoteRepository` asks of the server: one meeting, and
/// the votes recorded.
final class VotesServerSide {
  /// Creates the set-up for the server.
  new(this._server);

  final SetupServer _server;

  /// Makes the server hold [meeting] and nothing recorded.
  void serve(Meeting meeting) {
    _server.load(ServerContent(meetings: [meeting], recordedVotes: const []));
  }

  /// Replaces the meeting and keeps the votes recorded.
  void change(Meeting meeting) {
    _server.load(
      ServerContent(
        meetings: [meeting],
        recordedVotes: _server.backend.recordedVotes(),
      ),
    );
  }

  /// How many votes the server holds under the key of [vote].
  int recordedCount(Vote vote) => _server.backend
      .recordedVotes()
      .where((held) => held.idempotencyKey == vote.idempotencyKey)
      .length;
}

/// The set-up of the meetings, the way the contract suite of
/// `MeetingRepository` asks for it.
MeetingsServerSide meetingsServerSide(TestServer server) =>
    MeetingsServerSide(server);

/// The set-up of the documents, the way the contract suite of
/// `DocumentRepository` asks for it.
DocumentsServerSide documentsServerSide(TestServer server) =>
    DocumentsServerSide(server);

/// The set-up of the votes, the way the contract suite of `VoteRepository` asks
/// for it.
VotesServerSide votesServerSide(TestServer server) => VotesServerSide(server);
