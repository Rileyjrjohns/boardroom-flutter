import 'dart:typed_data';

import 'package:boardroom/application/ports/auth_session.dart';
import 'package:boardroom/application/ports/clock.dart';
import 'package:boardroom/domain/entities/document.dart';
import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/entities/resolution.dart';
import 'package:boardroom/domain/entities/session.dart';
import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/policies/session_expiry.dart';
import 'package:boardroom/domain/policies/voting_eligibility.dart';
import 'package:boardroom/domain/shared/constants.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/domain/value_objects/meeting_period.dart';
import 'package:boardroom/domain/value_objects/page.dart';
import 'package:boardroom/domain/value_objects/page_cursor.dart';
import 'package:boardroom/domain/value_objects/page_request.dart';
import 'package:boardroom/infrastructure/in_memory/simulated_network.dart';
import 'package:boardroom/infrastructure/pdf/create_document_pdf.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// What the simulated server holds. Server data, not user interface text: it is
/// in English whatever the language of the app.
@immutable
final class ServerContent {
  /// Creates the content of a server.
  const new({required this.meetings, required this.recordedVotes});

  /// The meetings with their agenda, documents and participants. A resolution
  /// carries no `recordedVote` here: a recorded vote belongs to its voter, so
  /// it is listed in [recordedVotes] and added to the resolution of the user
  /// who asks.
  final List<Meeting> meetings;

  /// The votes already recorded, whoever cast them.
  final List<Vote> recordedVotes;

  @override
  bool operator ==(Object other) =>
      other is ServerContent &&
      const DeepCollectionEquality().equals(meetings, other.meetings) &&
      const DeepCollectionEquality().equals(recordedVotes, other.recordedVotes);

  @override
  int get hashCode => Object.hash(
    const DeepCollectionEquality().hash(meetings),
    const DeepCollectionEquality().hash(recordedVotes),
  );

  @override
  String toString() =>
      'ServerContent(${meetings.length} meetings, '
      '${recordedVotes.length} recorded votes)';
}

/// Where the server learns who is calling: a session, as a real server would
/// learn it from the token a request carries. A session whose expiry has passed
/// is refused.
abstract interface class Caller {
  /// The session of the caller, or `null` when nobody is the caller.
  Future<Result<Session?, StorageReadFailedError>> current();
}

/// The caller of the requests of a device: the session stored on it.
final class AuthSessionCaller implements Caller {
  /// Makes the stored session of the [AuthSession] given the caller.
  const new(this._auth);

  final AuthSession _auth;

  @override
  Future<Result<Session?, StorageReadFailedError>> current() => _auth.current();
}

/// What an [InMemoryBackend] is built with.
@immutable
final class InMemoryBackendOptions {
  /// Creates the options of a backend.
  const new({
    required this.clock,
    required this.auth,
    required this.network,
    required this.content,
  });

  /// The clock of the server: the sessions expire on it, and it decides which
  /// list a meeting is in.
  final Clock clock;

  /// The caller of the requests that do not name one: the session stored on
  /// the device, which is how the in-memory repositories reach the server. The
  /// HTTP API names the caller of each request (see `MockApi`).
  final Caller auth;

  /// The connectivity of the server. Exposed as `InMemoryBackend.network`.
  final SimulatedNetwork network;

  /// What the server holds at the start.
  final ServerContent content;
}

/// Separates the instant and the id in a page cursor.
const String _cursorSeparator = ':';

/// The `cause` of the `unexpected` errors. Technical, and free of any value of
/// the query.
abstract final class _FailureCause {
  static const String invalidCursor = 'invalid page cursor';
  static const String invalidLimit = 'invalid page limit';
  static const String cursorNotBuilt = 'page cursor could not be built';
}

/// What the server sends for the content of a document: the file, who it was
/// made for and which version of the document it is. The HTTP API sends the
/// same three things (the body, the token's user, which the client knows, and
/// the `ETag`).
@immutable
final class ServedDocumentContent {
  /// Creates the content served to [userId].
  const new({required this.userId, required this.version, required this.bytes});

  /// The user the content was served to. Two users never share a download.
  final UserId userId;

  /// Identifies the version of the content. It changes when the content or the
  /// classification of the document does, so a download is never reused across
  /// versions. Opaque.
  final String version;

  /// The bytes of the PDF.
  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      other is ServedDocumentContent &&
      other.userId == userId &&
      other.version == version &&
      const ListEquality<int>().equals(bytes, other.bytes);

  @override
  int get hashCode =>
      Object.hash(userId, version, const ListEquality<int>().hash(bytes));

  @override
  String toString() =>
      'ServedDocumentContent(version: $version, ${bytes.length} bytes)';
}

/// Why a content cannot be held by the server.
enum ServerContentErrorCode implements StableValue {
  /// Two meetings have a resolution with the same id.
  duplicateResolutionId('duplicateResolutionId');

  new(this.value);

  @override
  final String value;
}

/// Two meetings of the content have a resolution with the same id. Resolution
/// ids are globally unique (see `ResolutionId`): the idempotency key of a vote
/// holds the resolution and the voter, not the meeting, so a shared id would
/// make a vote on one meeting look like a vote on the other.
@immutable
final class ServerContentError {
  /// Creates the error for [resolutionId].
  const new({required this.code, required this.resolutionId});

  /// Which rule the content breaks.
  final ServerContentErrorCode code;

  /// The id that two meetings share.
  final ResolutionId resolutionId;

  @override
  bool operator ==(Object other) =>
      other is ServerContentError &&
      other.code == code &&
      other.resolutionId == resolutionId;

  @override
  int get hashCode => Object.hash(code, resolutionId);

  @override
  String toString() => 'ServerContentError(${code.value})';
}

ServerContentError _duplicateResolutionId(ResolutionId resolutionId) =>
    ServerContentError(
      code: ServerContentErrorCode.duplicateResolutionId,
      resolutionId: resolutionId,
    );

/// A resolution id that two meetings share, or `null`. (Within a meeting the
/// domain checks it.)
ResolutionId? _findDuplicateResolutionId(List<Meeting> meetings) {
  final seen = <ResolutionId>{};
  for (final meeting in meetings) {
    for (final item in meeting.agenda) {
      final resolution = item.resolution;
      if (resolution == null) {
        continue;
      }
      if (!seen.add(resolution.id)) {
        return resolution.id;
      }
    }
  }
  return null;
}

/// What a page cursor holds: where in the order the next page starts.
@immutable
final class _CursorKey {
  const new(this.scheduledAt, this.id);

  new of(MeetingSummary meeting)
    : scheduledAt = meeting.scheduledAt,
      id = meeting.id;

  final int scheduledAt;
  final String id;
}

/// The largest whole number a JavaScript number holds exactly. The cursors are
/// shared with the other implementations of the API, which read an instant into
/// a `Number`.
const int _maxSafeInteger = 9007199254740991;

/// The simulated server behind the three remote repositories: one state,
/// shared by all of them, so that a vote recorded through one is seen by the
/// others. It behaves the way the port contracts describe a real one:
///
/// - every request enters the network first (`networkUnavailable` offline, then
///   the latency), then is authenticated (`unauthorized` without a valid
///   session);
/// - a user sees the meetings they take part in. Which of the two lists a
///   meeting is in is decided here, against the clock: upcoming ones soonest
///   first, past ones latest first. A meeting or a document that exists but
///   that the user may not have is refused with `forbidden`, and one that does
///   not exist is `notFound`. Telling them apart reveals that an id exists.
///   That is little here (ids are opaque, issued by the server, and a board is
///   a closed group), and it lets the client say "you no longer have access"
///   instead of "does not exist"; a server that wants to hide the existence
///   answers `notFound`, which the application treats the same way;
/// - pages are cut to the requested limit and continue after an opaque cursor
///   that stays valid when the lists change in between;
/// - a vote is recorded for the authenticated user only, once per resolution:
///   sending the same vote again succeeds, another choice is `alreadyVoted`.
///   The business rules are the ones of the domain (`checkVotingEligibility`),
///   applied at the time of the server, which stamps the vote with its own time
///   and never trusts `castAt`.
///
/// What it holds is immutable, so no client holds a reference it could change
/// the server through.
final class InMemoryBackend {
  new _(this._options) : network = _options.network;

  /// A server holding the content, or the reason the content is not acceptable:
  /// two meetings must not share a resolution id (see `ResolutionId`).
  static Result<InMemoryBackend, ServerContentError> create(
    InMemoryBackendOptions options,
  ) {
    final backend = InMemoryBackend._(options);
    return switch (backend.replaceContent(options.content)) {
      Err(:final error) => err(error),
      Ok() => ok(backend),
    };
  }

  final InMemoryBackendOptions _options;

  /// The connectivity of the server.
  final SimulatedNetwork network;

  Map<MeetingId, Meeting> _meetings = {};
  Map<IdempotencyKey, Vote> _votes = {};

  /// Counts the versions of the content: a download is never reused across two
  /// of them.
  int _revision = 0;

  /// Replaces everything the server holds, for a test that sets the world up.
  /// The content is refused, and the server keeps what it held, when two
  /// meetings share a resolution id.
  Result<void, ServerContentError> replaceContent(ServerContent content) {
    final duplicate = _findDuplicateResolutionId(content.meetings);
    if (duplicate != null) {
      return err(_duplicateResolutionId(duplicate));
    }

    _revision += 1;
    _meetings = {for (final meeting in content.meetings) meeting.id: meeting};
    _votes = {
      for (final vote in content.recordedVotes) vote.idempotencyKey: vote,
    };
    return ok<void>(null);
  }

  /// The votes the server holds, whoever cast them. For tests, not for a
  /// client.
  List<Vote> recordedVotes() => List.unmodifiable(_votes.values);

  /// A page of the meetings of [period] the caller takes part in.
  Future<Result<Page<MeetingSummary>, GatewayError>> listMeetings(
    MeetingPeriod period,
    PageRequest request, [
    Caller? caller,
  ]) async {
    final entered = await _enter(caller ?? _options.auth);
    return switch (entered) {
      Err(:final error) => err(error),
      Ok(:final value) => _pageOf(value, period, request),
    };
  }

  /// A meeting, with the recorded votes of the caller.
  Future<Result<Meeting, RepositoryError>> getMeeting(
    MeetingId id, [
    Caller? caller,
  ]) async {
    final entered = await _enter(caller ?? _options.auth);
    return switch (entered) {
      Err(:final error) => err(error),
      Ok(:final value) => _meetingFor(value, id),
    };
  }

  /// The metadata of a document.
  Future<Result<Document, RepositoryError>> getDocument(
    DocumentId id, [
    Caller? caller,
  ]) async {
    final entered = await _enter(caller ?? _options.auth);
    return switch (entered) {
      Err(:final error) => err(error),
      Ok(:final value) => _documentFor(value, id),
    };
  }

  /// The content of a document: a PDF with one page for each page of the
  /// document (up to a maximum, see `createDocumentPdf`), the user it was
  /// served to and the version of the content. The version is per revision of
  /// what the server holds: a download is never reused across two of them.
  Future<Result<ServedDocumentContent, RepositoryError>> fetchDocumentContent(
    DocumentId id, [
    Caller? caller,
  ]) async {
    final entered = await _enter(caller ?? _options.auth);
    return switch (entered) {
      Err(:final error) => err(error),
      Ok(:final value) => _contentFor(value, id),
    };
  }

  /// Records [vote] for the caller.
  Future<Result<void, AppError>> submitVote(Vote vote, [Caller? caller]) async {
    final entered = await _enter(caller ?? _options.auth);
    return switch (entered) {
      Err(:final error) => err(error),
      Ok(:final value) => _record(vote, value),
    };
  }

  /// The start of the request pipeline. The identity is read when the request
  /// is created, from the session of the caller at that moment, like a client
  /// that attaches its token before sending: nobody signed in is
  /// `unauthorized`, whatever the network. Then the request goes through the
  /// network, and the handler answers for the identity of the request, never
  /// for a user who signed in while it was on its way.
  Future<Result<UserId, GatewayError>> _enter(Caller caller) async {
    final userId = await _authenticatedUser(caller);
    if (userId == null) {
      return err(unauthorized());
    }

    final reached = await network.enter();
    if (reached case Err(:final error)) {
      return err(error);
    }
    return ok(userId);
  }

  Future<UserId?> _authenticatedUser(Caller caller) async {
    final current = await caller.current();
    final session = switch (current) {
      Ok(:final value) => value,
      Err() => null,
    };
    if (session == null) {
      return null;
    }
    return isSessionExpired(session, _options.clock.now())
        ? null
        : session.user.id;
  }

  Result<Page<MeetingSummary>, GatewayError> _pageOf(
    UserId userId,
    MeetingPeriod period,
    PageRequest request,
  ) {
    // The limit comes from outside: it is checked by the rules of the domain,
    // not trusted.
    final valid = createPageRequest(
      limit: request.limit,
      cursor: request.cursor,
    );
    if (valid is! Ok<PageRequest, ValidationError>) {
      return err(unexpected(_FailureCause.invalidLimit));
    }
    final limit = valid.value.limit;

    final now = _options.clock.now();
    final compare = _comparatorOf(period);
    final ordered =
        [
          for (final meeting in _meetings.values)
            if (findParticipant(meeting, userId) != null &&
                _periodOf(meeting, now) == period)
              meeting,
        ]..sort(
          (first, second) =>
              compare(_CursorKey.of(first), _CursorKey.of(second)),
        );

    var start = 0;
    final cursor = request.cursor;
    if (cursor != null) {
      final after = _decodeCursor(cursor);
      if (after == null) {
        return err(unexpected(_FailureCause.invalidCursor));
      }
      final firstAfter = ordered.indexWhere(
        (meeting) => compare(_CursorKey.of(meeting), after) > 0,
      );
      start = firstAfter == -1 ? ordered.length : firstAfter;
    }

    final items = ordered.skip(start).take(limit).map(_summaryOf).toList();
    if (items.isEmpty || start + limit >= ordered.length) {
      return ok(createPage(items));
    }
    final nextCursor = parsePageCursor(
      _encodeCursor(_CursorKey.of(items.last)),
    );
    return switch (nextCursor) {
      Ok(:final value) => ok(createPage(items, value)),
      Err() => err(unexpected(_FailureCause.cursorNotBuilt)),
    };
  }

  Result<Meeting, RepositoryError> _meetingFor(UserId userId, MeetingId id) {
    final meeting = _meetings[id];
    if (meeting == null) {
      return err(notFound());
    }
    if (findParticipant(meeting, userId) == null) {
      return err(forbidden());
    }
    return ok(_viewFor(meeting, userId));
  }

  Result<Document, RepositoryError> _documentFor(UserId userId, DocumentId id) {
    final found = _findDocument(id, userId);
    if (found == null) {
      return err(notFound());
    }
    return found.allowed ? ok(found.document) : err(forbidden());
  }

  Result<ServedDocumentContent, RepositoryError> _contentFor(
    UserId userId,
    DocumentId id,
  ) {
    final found = _findDocument(id, userId);
    if (found == null) {
      return err(notFound());
    }
    if (!found.allowed) {
      return err(forbidden());
    }
    return ok(
      ServedDocumentContent(
        userId: userId,
        version: '$_revision',
        bytes: createDocumentPdf(
          DocumentPdfSpec(
            title: found.document.title,
            pageCount: found.document.pageCount,
          ),
        ),
      ),
    );
  }

  /// The document, and whether the user may have it: they may when they take
  /// part in a meeting that lists it. `null` when no meeting lists it at all.
  ({Document document, bool allowed})? _findDocument(
    DocumentId id,
    UserId userId,
  ) {
    Document? found;
    for (final meeting in _meetings.values) {
      final document = meeting.documents.firstWhereOrNull(
        (candidate) => candidate.id == id,
      );
      if (document == null) {
        continue;
      }
      if (findParticipant(meeting, userId) != null) {
        return (document: document, allowed: true);
      }
      found ??= document;
    }
    return found == null ? null : (document: found, allowed: false);
  }

  /// The meeting as the user sees it: their own recorded votes on the
  /// resolutions.
  Meeting _viewFor(Meeting meeting, UserId userId) => meeting.copyWith(
    agenda: [
      for (final item in meeting.agenda)
        if (item.resolution case final resolution?)
          item.copyWith(resolution: _withRecordedVote(resolution, userId))
        else
          item,
    ],
  );

  Resolution _withRecordedVote(Resolution resolution, UserId userId) {
    final held = _votes[idempotencyKeyOf(resolution.id, userId)];
    return held == null
        ? resolution
        : resolution.copyWith(recordedVote: held.choice);
  }

  Result<void, AppError> _record(Vote vote, UserId userId) {
    // A vote is recorded for the user the request is authenticated as,
    // whoever queued it.
    if (vote.voterId != userId) {
      return err(unauthorized());
    }

    // A key that already holds a vote answers before any rule of eligibility:
    // the same choice is the same vote sent again (success, even if the
    // resolution has closed since), another choice is a second vote
    // (`alreadyVoted`, not `resolutionClosed`). The meeting is compared too, as
    // a safeguard: resolution ids are unique, so a vote held under the key of
    // another meeting cannot happen.
    final key = idempotencyKeyOf(vote.resolutionId, userId);
    final held = _votes[key];
    if (held != null && held.meetingId == vote.meetingId) {
      return held.choice == vote.choice
          ? ok<void>(null)
          : err(const AlreadyVotedError(source: AlreadyVotedSource.recorded));
    }

    final meeting = _meetings[vote.meetingId];
    if (meeting == null) {
      return err(ResolutionNotFoundError(resolutionId: vote.resolutionId));
    }

    final now = _options.clock.now();
    final eligible = checkVotingEligibility(
      VotingEligibilityInput(
        meeting: _viewFor(meeting, userId),
        resolutionId: vote.resolutionId,
        voterId: userId,
        queuedVotes: const [],
        now: now,
      ),
    );
    if (eligible case Err(:final error)) {
      return err(error);
    }

    // The server's time, not the `castAt` of a device whose clock the user
    // controls.
    _votes[key] = createVote(
      VoteInput(
        resolutionId: vote.resolutionId,
        meetingId: vote.meetingId,
        voterId: userId,
        choice: vote.choice,
        castAt: now,
      ),
    );
    return ok<void>(null);
  }
}

MeetingPeriod _periodOf(MeetingSummary meeting, Instant now) =>
    meeting.scheduledAt > now ? MeetingPeriod.upcoming : MeetingPeriod.past;

int _compareIds(String first, String second) {
  if (first == second) {
    return 0;
  }
  return first.compareTo(second) < 0 ? -1 : 1;
}

/// Upcoming meetings soonest first, past ones latest first, ties broken by id.
int Function(_CursorKey first, _CursorKey second) _comparatorOf(
  MeetingPeriod period,
) => (first, second) {
  final byTime = period == MeetingPeriod.upcoming
      ? first.scheduledAt - second.scheduledAt
      : second.scheduledAt - first.scheduledAt;
  return byTime != 0 ? byTime : _compareIds(first.id, second.id);
};

/// `<instant>:<encoded id>`. The id is encoded, so the separator cannot appear
/// inside it.
String _encodeCursor(_CursorKey key) =>
    '${key.scheduledAt}$_cursorSeparator${Uri.encodeComponent(key.id)}';

/// Exactly what `_encodeCursor` writes: a whole instant without sign or leading
/// zero, a separator, an encoded id.
final RegExp _cursorFormat = RegExp(r'^(0|[1-9][0-9]*):([^:]+)$');

_CursorKey? _decodeCursor(PageCursor cursor) {
  final match = _cursorFormat.firstMatch(cursor);
  final instant = match == null ? null : int.tryParse(match.group(1)!);
  final encodedId = match?.group(2);
  if (instant == null || encodedId == null || instant > _maxSafeInteger) {
    return null;
  }
  try {
    return _CursorKey(instant, Uri.decodeComponent(encodedId));
  } on Object {
    // A malformed escape sequence: a cursor this server did not write.
    return null;
  }
}

/// What a list shows: not the agenda, the documents nor the participants.
MeetingSummary _summaryOf(MeetingSummary meeting) => MeetingSummary(
  id: meeting.id,
  title: meeting.title,
  scheduledAt: meeting.scheduledAt,
  location: meeting.location,
);
