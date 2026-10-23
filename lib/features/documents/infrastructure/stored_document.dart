import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:json_annotation/json_annotation.dart';

part 'stored_document.g.dart';

// What the cache of documents keeps in a row of `document_entries`, apart from
// the owner, the instant and the location, which have columns of their own: the
// metadata of the document, as JSON, in the format of the database. It is the
// cache's own, like `stored_meeting.dart`, and not the DTO of the API, so that
// a change of the API (a field renamed) cannot make the rows already on the
// devices unreadable, and a change of what is stored is a decision of the
// cache. It happens to look like what the API wrote when the cache was first
// written, and a test holds a row exactly as that version wrote it and reads
// it. The meeting cache keeps the same four fields in the row of a meeting
// (`StoredMeetingDocument`): the two formats are each their own.
//
// The class checks that each field is there with the type that was stored and
// ignores the ones it does not know. The values themselves are checked by the
// factory of the domain.

/// A document as the cache keeps it.
@JsonSerializable(checked: true)
final class StoredDocument {
  /// Creates the stored form of a document.
  const new({
    required this.id,
    required this.title,
    required this.confidentiality,
    required this.pageCount,
  });

  /// Reads the stored form of a document, or throws a
  /// `CheckedFromJsonException` at the first field that is missing or has the
  /// wrong type.
  factory fromJson(Map<String, dynamic> json) => _$StoredDocumentFromJson(json);

  /// The identifier of the document.
  final String id;

  /// The title of the document.
  final String title;

  /// The level of confidentiality, as the cache names it.
  final String confidentiality;

  /// The number of pages.
  final num pageCount;

  /// The JSON object of this document.
  Map<String, dynamic> toJson() => _$StoredDocumentToJson(this);
}

/// What is written in a row for a document.
StoredDocument storedDocumentOf(Document document) => StoredDocument(
  id: document.id,
  title: document.title,
  confidentiality: document.confidentiality.value,
  pageCount: document.pageCount,
);

/// A document back from what the cache kept, through the factory of the
/// domain.
Result<Document, ValidationError> documentOf(StoredDocument stored) => andThen(
  parseDocumentId(stored.id),
  (id) => andThen(
    parseConfidentialityLevel(stored.confidentiality),
    (confidentiality) => createDocument(
      DocumentInput(
        id: id,
        title: stored.title,
        confidentiality: confidentiality,
        pageCount: stored.pageCount,
      ),
    ),
  ),
);
