import 'dart:convert';

import 'package:boardroom/app/dev/in_memory/fixtures/fixture_schemas.dart';
import 'package:boardroom/app/dev/in_memory/in_memory_auth_session.dart';
import 'package:boardroom/app/dev/in_memory/in_memory_backend.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/core/infrastructure/shared/issue_paths.dart';
import 'package:boardroom/features/auth/domain/entities/user.dart';
import 'package:boardroom/features/auth/infrastructure/dto/session_dto.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/infrastructure/dto/meeting_dto.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:boardroom/features/votes/infrastructure/dto/vote_dto.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

// Reads the fixtures of docs/spec/fixtures into the content of the simulated
// server. The files are data from outside the code: they are checked, then
// turned into domain objects through the factories of the domain, and a flaw is
// a `FixtureError`, never an exception.
//
// Every date of the files is relative to their `referenceDate`. Loading shifts
// all of them by the same amount, a whole number of days:
// `floor((now - referenceDate) / one day)` days. The timeline keeps its shape
// and the meetings keep their time of day (09:00 stays 09:00, in UTC), whatever
// the day the app starts. A whole number of days is less than a day short of
// the exact `now - referenceDate`, so the files must keep a margin of a day
// around the reference date, which loading checks: that is what keeps an
// upcoming meeting upcoming and a past one past.

/// The room the files leave around the reference date: every meeting and every
/// closing time is at least this far from it, on either side, and no vote was
/// cast after it. The whole-day shift falls short of the exact
/// `now - referenceDate` by less than this, so with this margin no instant of
/// the files can cross `now`.
const int _timelineMarginMillis = millisPerDay;

/// The names of the places of the files that a `FixtureError` points at. They
/// are the keys of the files (docs/spec/fixtures/README.md).
abstract final class _Place {
  static const String accounts = 'accounts';
  static const String meetings = 'meetings';
  static const String recordedVotes = 'recordedVotes';
  static const String referenceDate = 'referenceDate';
  static const String demoUserId = 'demoUserId';
  static const String scheduledAt = 'scheduledAt';
  static const String castAt = 'castAt';
  static const String agenda = 'agenda';
  static const String resolution = 'resolution';
  static const String closesAt = 'closesAt';
  static const String documents = 'documents';
  static const String id = 'id';
  static const String resolutionId = 'resolutionId';
  static const String meetingId = 'meetingId';
  static const String voterId = 'voterId';
}

/// The files of the fixtures.
enum FixtureFile implements StableValue {
  /// The accounts that can sign in.
  accounts('accounts.json'),

  /// The meetings.
  meetings('meetings.json'),

  /// The votes already recorded.
  recordedVotes('recorded-votes.json');

  new(this.value);

  @override
  final String value;
}

/// The content of the files, as read from disk or from the asset bundle and not
/// yet parsed nor checked.
@immutable
final class FixtureFiles {
  /// Creates the content of the three files.
  const new({
    required this.accounts,
    required this.meetings,
    required this.recordedVotes,
  });

  /// The text of `accounts.json`.
  final String accounts;

  /// The text of `meetings.json`.
  final String meetings;

  /// The text of `recorded-votes.json`.
  final String recordedVotes;
}

/// Why a fixture cannot be loaded.
enum FixtureErrorCode implements StableValue {
  /// A field is missing, or has the wrong type.
  invalidShape('invalidShape'),

  /// A value breaks a rule of the domain (a blank title, an unknown status, an
  /// instant out of range).
  invalidValue('invalidValue'),

  /// The files do not share the same `referenceDate`: they are not from the
  /// same generation.
  referenceDateMismatch('referenceDateMismatch'),

  /// An id points to something that is not in the files.
  unknownReference('unknownReference'),

  /// Two members that must be unique share an identity.
  duplicate('duplicate'),

  /// A meeting or a closing time is less than a day from the reference date,
  /// or a vote was cast after it: shifted by whole days, it could fall on the
  /// other side of the clock.
  timelineMargin('timelineMargin');

  new(this.value);

  @override
  final String value;
}

/// Where and why a fixture was refused. `detail` names the file and the place
/// in it (`meetings.2.title`), never a value: the same convention as for the
/// answers of the API.
@immutable
final class FixtureError {
  /// Creates the error of a fixture refused at [detail].
  const new({required this.code, required this.file, required this.detail});

  /// Why the fixture was refused.
  final FixtureErrorCode code;

  /// The file that was refused.
  final FixtureFile file;

  /// The file and the place in it, without any value.
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is FixtureError &&
      other.code == code &&
      other.file == file &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(code, file, detail);

  @override
  String toString() => 'FixtureError(${code.value}, $detail)';
}

/// What the fixtures make: the content of the simulated server and the accounts
/// that can sign in.
@immutable
final class SeedData {
  /// Creates the seed of a server.
  const new({
    required this.accounts,
    required this.demoUser,
    required this.content,
  });

  /// The accounts that can sign in.
  final List<DemoAccount> accounts;

  /// The demo user: the account that is signed in at start by the mock
  /// configuration.
  final User demoUser;

  /// What the simulated server holds.
  final ServerContent content;

  @override
  bool operator ==(Object other) =>
      other is SeedData &&
      const DeepCollectionEquality().equals(accounts, other.accounts) &&
      other.demoUser == demoUser &&
      other.content == content;

  @override
  int get hashCode => Object.hash(
    const DeepCollectionEquality().hash(accounts),
    demoUser,
    content,
  );

  @override
  String toString() =>
      'SeedData(${accounts.length} accounts, demo user: ${demoUser.id}, '
      '$content)';
}

FixtureError _fixtureError(
  FixtureErrorCode code,
  FixtureFile file,
  String place, [
  String? reason,
]) {
  final suffix = reason == null ? '' : ' ($reason)';
  return FixtureError(
    code: code,
    file: file,
    detail: '${file.value}: $place$suffix',
  );
}

String _violation(ValidationError error) =>
    '${error.field.value} ${error.rule.value}';

/// The content of a file, if it is JSON and has the shape of its wire class.
Result<T, FixtureError> _parseFile<T>(
  FixtureFile file,
  T Function(Map<String, dynamic> json) fromJson,
  String content,
) {
  final Object? json;
  try {
    json = jsonDecode(content);
  } on FormatException {
    return err(_fixtureError(FixtureErrorCode.invalidShape, file, rootPath));
  }
  return switch (decodeWire(json, fromJson)) {
    Ok(:final value) => ok(value),
    Err(:final error) => err(
      _fixtureError(FixtureErrorCode.invalidShape, file, error.issuePaths),
    ),
  };
}

/// The members of a list through [read], or the position of the first one it
/// refuses.
Result<List<T>, FixtureError> _readAll<W, T>(
  FixtureFile file,
  String list,
  List<W> members,
  Result<T, ValidationError> Function(W member) read,
) {
  final values = <T>[];
  for (final (index, member) in members.indexed) {
    switch (read(member)) {
      case Ok(:final value):
        values.add(value);
      case Err(:final error):
        return err(
          _fixtureError(
            FixtureErrorCode.invalidValue,
            file,
            '$list.$index',
            _violation(error),
          ),
        );
    }
  }
  return ok(values);
}

/// The place of the first member whose key is the one of an earlier member, or
/// `null`.
int? _firstDuplicate<T>(List<T> members, String Function(T member) keyOf) {
  final seen = <String>{};
  for (final (index, member) in members.indexed) {
    if (!seen.add(keyOf(member))) {
      return index;
    }
  }
  return null;
}

/// The shift of the dates of the files, in milliseconds: a whole number of
/// days, the number of complete days from the reference date to `now`. A `now`
/// before the reference date gives a negative number of days, rounded to the
/// earlier day (floor, not truncation towards zero): one millisecond before the
/// reference date is a day back.
int _shiftOf(Instant now, int referenceDate) {
  final elapsed = now - referenceDate;
  return (elapsed - elapsed % millisPerDay) ~/ millisPerDay * millisPerDay;
}

/// The place of the first instant of the files that the whole-day shift could
/// move to the other side of the clock, or `null`: a meeting or a closing time
/// less than the margin from the reference date (either side), or a vote cast
/// after it.
FixtureError? _timelineViolation(
  List<MeetingWire> meetings,
  List<VoteRequestWire> votes,
  int referenceDate,
) {
  bool tooClose(int instant) =>
      (instant - referenceDate).abs() < _timelineMarginMillis;
  FixtureError flaw(FixtureFile file, String place) =>
      _fixtureError(FixtureErrorCode.timelineMargin, file, place);

  for (final (index, meeting) in meetings.indexed) {
    if (tooClose(meeting.scheduledAt)) {
      return flaw(
        FixtureFile.meetings,
        '${_Place.meetings}.$index.${_Place.scheduledAt}',
      );
    }
    for (final (position, item) in meeting.agenda.indexed) {
      final closesAt = item.resolution?.closesAt;
      if (closesAt != null && tooClose(closesAt)) {
        const resolution = '${_Place.resolution}.${_Place.closesAt}';
        return flaw(
          FixtureFile.meetings,
          '${_Place.meetings}.$index.${_Place.agenda}.$position.$resolution',
        );
      }
    }
  }
  for (final (index, vote) in votes.indexed) {
    if (vote.castAt > referenceDate) {
      return flaw(
        FixtureFile.recordedVotes,
        '${_Place.recordedVotes}.$index.${_Place.castAt}',
      );
    }
  }
  return null;
}

/// The meeting with every instant moved by [delta] milliseconds. The domain
/// checks the result.
MeetingWire _shiftMeeting(MeetingWire meeting, int delta) => MeetingWire(
  id: meeting.id,
  title: meeting.title,
  scheduledAt: meeting.scheduledAt + delta,
  location: meeting.location,
  agenda: [
    for (final item in meeting.agenda)
      if (item.resolution case final resolution?)
        AgendaItemWire(
          id: item.id,
          position: item.position,
          title: item.title,
          description: item.description,
          resolution: ResolutionWire(
            id: resolution.id,
            title: resolution.title,
            description: resolution.description,
            status: resolution.status,
            closesAt: resolution.closesAt == null
                ? null
                : resolution.closesAt! + delta,
            recordedVote: resolution.recordedVote,
          ),
        )
      else
        item,
  ],
  documents: meeting.documents,
  participants: meeting.participants,
);

/// The meeting that holds each resolution, to check what the recorded votes
/// point to.
Map<ResolutionId, Meeting> _meetingsByResolution(List<Meeting> meetings) => {
  for (final meeting in meetings)
    for (final item in meeting.agenda)
      if (item.resolution case final resolution?) resolution.id: meeting,
};

/// The position of the first meeting that lists a document an earlier meeting
/// lists, or `null`.
int? _firstSharedDocument(List<Meeting> meetings) {
  final seen = <String>{};
  for (final (index, meeting) in meetings.indexed) {
    for (final document in meeting.documents) {
      if (!seen.add(document.id)) {
        return index;
      }
    }
  }
  return null;
}

/// The content of the simulated server read from the fixtures, with every date
/// shifted by a whole number of days (the complete days from the reference date
/// to [now], see `_shiftOf`), or the first flaw found: a file that is not JSON
/// or breaks its schema, files from different generations, a meeting or a
/// closing time within a day of the reference date, a value that breaks a rule
/// of the domain, an id that points to nothing, a duplicate. Nothing is thrown.
Result<SeedData, FixtureError> loadFixtures(FixtureFiles files, Instant now) {
  final accountsFile = _parseFile(
    FixtureFile.accounts,
    AccountsFileWire.fromJson,
    files.accounts,
  );
  if (accountsFile case Err(:final error)) {
    return err(error);
  }
  final meetingsFile = _parseFile(
    FixtureFile.meetings,
    MeetingsFileWire.fromJson,
    files.meetings,
  );
  if (meetingsFile case Err(:final error)) {
    return err(error);
  }
  final votesFile = _parseFile(
    FixtureFile.recordedVotes,
    RecordedVotesFileWire.fromJson,
    files.recordedVotes,
  );
  if (votesFile case Err(:final error)) {
    return err(error);
  }
  final accountsWire =
      (accountsFile as Ok<AccountsFileWire, FixtureError>).value;
  final meetingsWire =
      (meetingsFile as Ok<MeetingsFileWire, FixtureError>).value;
  final votesWire =
      (votesFile as Ok<RecordedVotesFileWire, FixtureError>).value;

  final referenceDate = accountsWire.referenceDate;
  for (final (file, date) in [
    (FixtureFile.meetings, meetingsWire.referenceDate),
    (FixtureFile.recordedVotes, votesWire.referenceDate),
  ]) {
    if (date != referenceDate) {
      return err(
        _fixtureError(
          FixtureErrorCode.referenceDateMismatch,
          file,
          _Place.referenceDate,
        ),
      );
    }
  }
  final delta = _shiftOf(now, referenceDate);

  final read = _readAll<AccountWire, DemoAccount>(
    FixtureFile.accounts,
    _Place.accounts,
    accountsWire.accounts,
    (account) => map(
      toUser(account.user),
      (user) => DemoAccount(user: user, password: account.password),
    ),
  );
  if (read case Err(:final error)) {
    return err(error);
  }
  final accounts = (read as Ok<List<DemoAccount>, FixtureError>).value;
  final duplicateAccount =
      _firstDuplicate(accounts, (account) => account.user.id) ??
      _firstDuplicate(accounts, (account) => account.user.email);
  if (duplicateAccount != null) {
    return err(
      _fixtureError(
        FixtureErrorCode.duplicate,
        FixtureFile.accounts,
        '${_Place.accounts}.$duplicateAccount',
      ),
    );
  }
  final demoUser = accounts
      .where((account) => account.user.id == accountsWire.demoUserId)
      .map((account) => account.user)
      .firstOrNull;
  if (demoUser == null) {
    return err(
      _fixtureError(
        FixtureErrorCode.unknownReference,
        FixtureFile.accounts,
        _Place.demoUserId,
      ),
    );
  }

  final outOfMargin = _timelineViolation(
    meetingsWire.meetings,
    votesWire.recordedVotes,
    referenceDate,
  );
  if (outOfMargin != null) {
    return err(outOfMargin);
  }

  final meetingsRead = _readAll<MeetingWire, Meeting>(
    FixtureFile.meetings,
    _Place.meetings,
    meetingsWire.meetings,
    (meeting) => toMeeting(_shiftMeeting(meeting, delta)),
  );
  if (meetingsRead case Err(:final error)) {
    return err(error);
  }
  final meetings = (meetingsRead as Ok<List<Meeting>, FixtureError>).value;
  final duplicateMeeting = _firstDuplicate(meetings, (meeting) => meeting.id);
  if (duplicateMeeting != null) {
    return err(
      _fixtureError(
        FixtureErrorCode.duplicate,
        FixtureFile.meetings,
        '${_Place.meetings}.$duplicateMeeting.${_Place.id}',
      ),
    );
  }
  final sharedDocument = _firstSharedDocument(meetings);
  if (sharedDocument != null) {
    return err(
      _fixtureError(
        FixtureErrorCode.duplicate,
        FixtureFile.meetings,
        '${_Place.meetings}.$sharedDocument.${_Place.documents}',
      ),
    );
  }

  final votesRead = _readAll<VoteRequestWire, Vote>(
    FixtureFile.recordedVotes,
    _Place.recordedVotes,
    votesWire.recordedVotes,
    (vote) => toVote(
      VoteRequestWire(
        resolutionId: vote.resolutionId,
        meetingId: vote.meetingId,
        voterId: vote.voterId,
        choice: vote.choice,
        castAt: vote.castAt + delta,
      ),
    ),
  );
  if (votesRead case Err(:final error)) {
    return err(error);
  }
  final recordedVotes = (votesRead as Ok<List<Vote>, FixtureError>).value;
  final unknown = _unknownReference(meetings, recordedVotes);
  if (unknown != null) {
    return err(unknown);
  }
  final duplicateVote = _firstDuplicate(
    recordedVotes,
    (vote) => vote.idempotencyKey,
  );
  if (duplicateVote != null) {
    return err(
      _fixtureError(
        FixtureErrorCode.duplicate,
        FixtureFile.recordedVotes,
        '${_Place.recordedVotes}.$duplicateVote',
      ),
    );
  }

  return ok(
    SeedData(
      accounts: accounts,
      demoUser: demoUser,
      content: ServerContent(meetings: meetings, recordedVotes: recordedVotes),
    ),
  );
}

/// The first recorded vote that points to a resolution, a meeting or a voter
/// the files do not have.
FixtureError? _unknownReference(List<Meeting> meetings, List<Vote> votes) {
  final held = _meetingsByResolution(meetings);
  FixtureError unknown(String place) => _fixtureError(
    FixtureErrorCode.unknownReference,
    FixtureFile.recordedVotes,
    place,
  );
  for (final (index, vote) in votes.indexed) {
    final meeting = held[vote.resolutionId];
    if (meeting == null) {
      return unknown('${_Place.recordedVotes}.$index.${_Place.resolutionId}');
    }
    if (meeting.id != vote.meetingId) {
      return unknown('${_Place.recordedVotes}.$index.${_Place.meetingId}');
    }
    if (findParticipant(meeting, vote.voterId) == null) {
      return unknown('${_Place.recordedVotes}.$index.${_Place.voterId}');
    }
  }
  return null;
}
