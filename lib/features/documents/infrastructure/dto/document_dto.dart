import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:json_annotation/json_annotation.dart';

part 'document_dto.g.dart';

// The metadata of a document of the API: `GET /documents/{id}`. Its content,
// `GET /documents/{id}/content`, is a file and not JSON: it has no schema (see
// `HttpClient.download`).

/// The metadata of a document as the API writes it.
@JsonSerializable(checked: true)
final class DocumentWire {
  /// Creates the wire form of a document.
  const new({
    required this.id,
    required this.title,
    required this.confidentiality,
    required this.pageCount,
  });

  /// Reads the wire form of a document, or throws a `CheckedFromJsonException`
  /// at the first field that is missing or has the wrong type. Fields it does
  /// not know are ignored.
  factory fromJson(Map<String, dynamic> json) => _$DocumentWireFromJson(json);

  /// The identifier of the document.
  final String id;

  /// The title of the document.
  final String title;

  /// The confidentiality level, as the API names it.
  final String confidentiality;

  /// The number of pages the document says it has.
  final num pageCount;

  /// The JSON object of this document.
  Map<String, dynamic> toJson() => _$DocumentWireToJson(this);
}

/// The document a wire form describes, through the factories of the domain.
Result<Document, ValidationError> toDocument(DocumentWire wire) => andThen(
  parseDocumentId(wire.id),
  (id) => andThen(
    parseConfidentialityLevel(wire.confidentiality),
    (confidentiality) => createDocument(
      DocumentInput(
        id: id,
        title: wire.title,
        confidentiality: confidentiality,
        pageCount: wire.pageCount,
      ),
    ),
  ),
);

/// A document, written as the API writes it.
DocumentWire toDocumentWire(Document document) => DocumentWire(
  id: document.id,
  title: document.title,
  confidentiality: document.confidentiality.value,
  pageCount: document.pageCount,
);
