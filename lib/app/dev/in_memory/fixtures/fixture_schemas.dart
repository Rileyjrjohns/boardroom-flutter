import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/features/auth/infrastructure/dto/session_dto.dart';
import 'package:boardroom/features/meetings/infrastructure/dto/meeting_dto.dart';
import 'package:boardroom/features/votes/infrastructure/dto/vote_dto.dart';
import 'package:json_annotation/json_annotation.dart';

part 'fixture_schemas.g.dart';

// The files of docs/spec/fixtures (see docs/spec/fixtures/README.md). Every
// file
// is an object whose `referenceDate` comes first. What the HTTP API has an
// equivalent for is read with the wire class of the API
// (docs/api.md, `dto/` of `lib/features/*/infrastructure`): a meeting is a
// `GET /meetings/{id}` answer, a recorded vote is the body of `POST /votes`, a
// user is the `user` of a sign-in answer. What the API does not expose (the
// accounts and their password, the votes already recorded) is described here
// and nowhere else. Like the API wire classes, these check that each field is
// there and has the right type, ignore the fields they do not know, and leave
// the values to the domain factories.

/// An account of `accounts.json`: a user and the password of the simulation.
@JsonSerializable(checked: true, explicitToJson: true)
final class AccountWire {
  /// Creates the wire form of an account.
  const new({required this.user, required this.password});

  /// Reads an account, or throws a `CheckedFromJsonException` at the first
  /// field that is missing or has the wrong type.
  factory fromJson(Map<String, dynamic> json) => _$AccountWireFromJson(json);

  /// The user of the account.
  final UserWire user;

  /// The password of the simulation.
  final String password;

  /// The JSON object of this account.
  Map<String, dynamic> toJson() => _$AccountWireToJson(this);
}

/// `accounts.json`.
@JsonSerializable(checked: true, explicitToJson: true)
final class AccountsFileWire {
  /// Creates the wire form of the file.
  const new({
    required this.referenceDate,
    required this.accounts,
    required this.demoUserId,
  });

  /// Reads the file, or throws a `CheckedFromJsonException` at the first field
  /// that is missing or has the wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$AccountsFileWireFromJson(json);

  /// The instant every date of the files is relative to, in milliseconds since
  /// the epoch.
  @JsonKey(fromJson: readInstantMillis, toJson: writeInstantMillis)
  final int referenceDate;

  /// The accounts that can sign in, with the password of the simulation.
  final List<AccountWire> accounts;

  /// The account that is signed in at start by the mock configuration.
  final String demoUserId;

  /// The JSON object of this file.
  Map<String, dynamic> toJson() => _$AccountsFileWireToJson(this);
}

/// `meetings.json`.
@JsonSerializable(checked: true, explicitToJson: true)
final class MeetingsFileWire {
  /// Creates the wire form of the file.
  const new({required this.referenceDate, required this.meetings});

  /// Reads the file, or throws a `CheckedFromJsonException` at the first field
  /// that is missing or has the wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$MeetingsFileWireFromJson(json);

  /// The instant every date of the files is relative to, in milliseconds since
  /// the epoch.
  @JsonKey(fromJson: readInstantMillis, toJson: writeInstantMillis)
  final int referenceDate;

  /// The meetings, as `GET /meetings/{id}` gives them.
  final List<MeetingWire> meetings;

  /// The JSON object of this file.
  Map<String, dynamic> toJson() => _$MeetingsFileWireToJson(this);
}

/// `recorded-votes.json`.
@JsonSerializable(checked: true, explicitToJson: true)
final class RecordedVotesFileWire {
  /// Creates the wire form of the file.
  const new({required this.referenceDate, required this.recordedVotes});

  /// Reads the file, or throws a `CheckedFromJsonException` at the first field
  /// that is missing or has the wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$RecordedVotesFileWireFromJson(json);

  /// The instant every date of the files is relative to, in milliseconds since
  /// the epoch.
  @JsonKey(fromJson: readInstantMillis, toJson: writeInstantMillis)
  final int referenceDate;

  /// The votes already recorded, as the body of `POST /votes` gives them.
  final List<VoteRequestWire> recordedVotes;

  /// The JSON object of this file.
  Map<String, dynamic> toJson() => _$RecordedVotesFileWireToJson(this);
}
