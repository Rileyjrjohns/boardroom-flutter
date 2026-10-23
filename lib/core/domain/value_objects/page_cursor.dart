import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';

const int _maxCursorLength = 512;

/// Where the next page starts. Opaque: the remote source builds it, the app
/// hands it back unchanged. Nothing may be inferred from its content, except
/// that it is well-formed UTF-16: it is put in a URL, and a lone surrogate
/// cannot be encoded.
///
/// A `String` at runtime (an extension type), made by [parsePageCursor] only.
extension type const PageCursor._(String _cursor) implements String;

/// Validates [raw]: trimmed, 1 to 512 characters, well-formed UTF-16.
Result<PageCursor, ValidationError> parsePageCursor(String raw) => andThen(
  requireText(ValidationField.pageCursor, raw, _maxCursorLength),
  (cursor) => isWellFormedText(cursor)
      ? ok(PageCursor._(cursor))
      : err(
          validationError(
            ValidationField.pageCursor,
            ValidationRule.invalidFormat,
          ),
        ),
);
