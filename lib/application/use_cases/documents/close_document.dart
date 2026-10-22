import 'package:boardroom/application/shared/screen_protection_coordinator.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';

/// What [CloseDocument] needs.
abstract interface class CloseDocumentDeps {
  /// The instance shared with `OpenDocument`.
  ScreenProtectionCoordinator get screenProtectionCoordinator;
}

/// Called when the viewer leaves a document. The screen protection is turned
/// off only if no other confidential document is still open (see
/// [ScreenProtectionCoordinator]). A document that was not opened by
/// `OpenDocument`, or is already closed, is ignored.
final class CloseDocument {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final CloseDocumentDeps _deps;

  /// Closes the document [documentId], the one the viewer leaves.
  Future<Result<void, ScreenProtectionError>> execute({
    required DocumentId documentId,
  }) => _deps.screenProtectionCoordinator.release(documentId);
}
