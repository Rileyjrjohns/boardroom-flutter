import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';

const int _maxLocationLength = 2048;

/// An opaque reference to where the content of a document can be read right now
/// (a file in the private storage of the app, for example). Produced by an
/// adapter, consumed by the viewer, never interpreted by the domain or the
/// application: they only carry it from one to the other.
///
/// A `String` at runtime (an extension type), made by [parseDocumentLocation]
/// only.
extension type const DocumentLocation._(String _location) implements String;

/// Validates [raw]: trimmed, 1 to 2048 characters.
Result<DocumentLocation, ValidationError> parseDocumentLocation(String raw) =>
    map(
      requireText(ValidationField.documentLocation, raw, _maxLocationLength),
      DocumentLocation._,
    );
