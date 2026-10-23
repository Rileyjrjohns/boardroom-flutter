import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';

const int _maxIdentifierLength = 128;

/// What a path reads as a directory, so an id cannot be either: `/meetings/..`
/// is `/`.
const List<String> _directoryNames = ['.', '..'];

/// Identifiers are opaque: they come from the remote source and are never
/// interpreted, so they are kept as received. They must only be usable as a key
/// and as a segment of a path: not blank, not absurdly long, well-formed UTF-16
/// (a lone surrogate cannot be encoded), and neither of the directory names `.`
/// and `..`, which a URL would resolve instead of passing on.
Result<String, ValidationError> _parseIdentifier(
  ValidationField field,
  String raw,
) {
  if (trimText(raw).isEmpty) {
    return err(validationError(field, ValidationRule.required));
  }
  if (raw.length > _maxIdentifierLength) {
    return err(validationError(field, ValidationRule.tooLong));
  }
  if (!isWellFormedText(raw) || _directoryNames.contains(raw)) {
    return err(validationError(field, ValidationRule.invalidFormat));
  }
  return ok(raw);
}

/// The id of a user. A `String` at runtime (an extension type), made by
/// [parseUserId] only.
extension type const UserId._(String _id) implements String;

/// The id of a meeting. A `String` at runtime, made by [parseMeetingId] only.
extension type const MeetingId._(String _id) implements String;

/// The id of an agenda item. A `String` at runtime, made by
/// [parseAgendaItemId] only.
extension type const AgendaItemId._(String _id) implements String;

/// Resolution ids are globally unique: no two meetings have a resolution with
/// the same id. The idempotency key of a vote is built from the resolution and
/// the voter, and does not hold the meeting, so a shared id would make a vote
/// on one meeting look like a vote on the other. The remote source guarantees
/// it, and an adapter that simulates one refuses a content that breaks it.
///
/// A `String` at runtime, made by [parseResolutionId] only.
extension type const ResolutionId._(String _id) implements String;

/// The id of a document. A `String` at runtime, made by [parseDocumentId] only.
extension type const DocumentId._(String _id) implements String;

/// Validates [raw] as the id of a user.
Result<UserId, ValidationError> parseUserId(String raw) =>
    map(_parseIdentifier(ValidationField.userId, raw), UserId._);

/// Validates [raw] as the id of a meeting.
Result<MeetingId, ValidationError> parseMeetingId(String raw) =>
    map(_parseIdentifier(ValidationField.meetingId, raw), MeetingId._);

/// Validates [raw] as the id of an agenda item.
Result<AgendaItemId, ValidationError> parseAgendaItemId(String raw) =>
    map(_parseIdentifier(ValidationField.agendaItemId, raw), AgendaItemId._);

/// Validates [raw] as the id of a resolution.
Result<ResolutionId, ValidationError> parseResolutionId(String raw) =>
    map(_parseIdentifier(ValidationField.resolutionId, raw), ResolutionId._);

/// Validates [raw] as the id of a document.
Result<DocumentId, ValidationError> parseDocumentId(String raw) =>
    map(_parseIdentifier(ValidationField.documentId, raw), DocumentId._);
