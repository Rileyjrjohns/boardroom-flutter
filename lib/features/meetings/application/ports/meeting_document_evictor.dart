import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';

/// Where a document a meeting lists is dropped from the device when the user
/// may no longer see that meeting. A meeting lists documents, so the rule "the
/// documents of a meeting that the server refuses go with it" is the meeting's;
/// who keeps a copy of a document is not, so the copy is reached through this
/// port, which the feature that keeps documents implements.
abstract interface class MeetingDocumentEvictor {
  /// Removes the copy of the document [id] that [owner] kept on the device,
  /// with its content. Succeeds when there is none.
  Future<Result<void, StorageWriteFailedError>> evict(
    UserId owner,
    DocumentId id,
  );
}
