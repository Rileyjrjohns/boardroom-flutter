import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'document.freezed.dart';

/// The longest title of a document, an agenda item, a resolution or a meeting,
/// in UTF-16 code units, once trimmed.
const int maxTitleLength = 300;

const int _maxPageCount = 10000;

/// How sensitive a document is.
enum ConfidentialityLevel implements StableValue {
  /// Anyone may read it.
  public('public'),

  /// For the members of the organisation.
  internal('internal'),

  /// Shown with its screen protected.
  confidential('confidential');

  new(this.value);

  @override
  final String value;
}

/// Parses the stable string [raw] into a [ConfidentialityLevel].
Result<ConfidentialityLevel, ValidationError> parseConfidentialityLevel(
  String raw,
) {
  final level = findConstant(ConfidentialityLevel.values, raw);
  return level == null
      ? err(
          validationError(
            ValidationField.confidentialityLevel,
            ValidationRule.unknownValue,
          ),
        )
      : ok(level);
}

/// The metadata of a document attached to a meeting. Its content is read
/// through a location.
@freezed
abstract class Document with _$Document {
  /// Creates a document from validated parts. Use [createDocument].
  const factory({
    required DocumentId id,
    required String title,
    required ConfidentialityLevel confidentiality,
    required int pageCount,
  }) = _Document;
}

/// What [createDocument] needs to build a document.
final class DocumentInput {
  /// Creates the input of [createDocument].
  const new({
    required this.id,
    required this.title,
    required this.confidentiality,
    required this.pageCount,
  });

  /// The id of the document.
  final DocumentId id;

  /// The title, trimmed by [createDocument].
  final String title;

  /// How sensitive the document is.
  final ConfidentialityLevel confidentiality;

  /// A whole number between 1 and 10 000. It is a `num` because it comes from
  /// outside (a decoded answer) and may be a fraction.
  final num pageCount;
}

/// Builds a document. The title is trimmed and must not be blank nor longer
/// than [maxTitleLength]; the page count must be a whole number between 1 and
/// 10 000.
Result<Document, ValidationError> createDocument(DocumentInput input) =>
    andThen(
      requireText(ValidationField.title, input.title, maxTitleLength),
      (title) => andThen(
        requireIntegerInRange(
          ValidationField.pageCount,
          input.pageCount,
          1,
          _maxPageCount,
        ),
        (pageCount) => ok(
          Document(
            id: input.id,
            title: title,
            confidentiality: input.confidentiality,
            pageCount: pageCount,
          ),
        ),
      ),
    );

/// A confidential document is shown with its screen protected (every document
/// carries a watermark).
bool isConfidential(Document document) =>
    document.confidentiality == ConfidentialityLevel.confidential;
