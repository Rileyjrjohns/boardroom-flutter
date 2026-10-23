import 'dart:convert';
import 'dart:typed_data';

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/core/infrastructure/shared/sha256.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:meta/meta.dart';

/// The extension of the files of the documents.
const String _fileExtension = '.pdf';

/// The `cause` of the error a download that could not be kept becomes.
const String _notStoredCause = 'content not stored';

/// What the monitoring is told the content was, when it could not be written.
const String _contentResource = 'documentContent';

/// The name of the file that holds the content of a document for a user, in a
/// version. It is the digest of the three, so:
///
/// - two users never share a file, and a new version never reuses the file of
///   the one before: downloading is the only way a file comes to exist, and it
///   is named for who it was downloaded for and which version it is;
/// - the same triple always gives the same name, so asking for the same content
///   twice says the same place;
/// - the name is short and made of hexadecimal digits, which every file system
///   accepts and which cannot collide with another name by case, by a separator
///   or by the way a character is written, whatever the identifiers contain
///   (they are free text); and it tells nothing of the user nor the document to
///   anyone who lists the directory.
///
/// The parts go through JSON so that they are never joined in one text:
/// `["a|b","c"]` and `["a","b|c"]` are two names.
String documentFileName(UserId owner, DocumentId id, String version) =>
    '${sha256Hex(jsonEncode([owner, id, version]))}$_fileExtension';

/// A download to keep.
@immutable
final class DownloadedDocument {
  /// Creates a download of [bytes].
  const new({
    required this.userId,
    required this.documentId,
    required this.version,
    required this.bytes,
  });

  /// The user the content was downloaded for.
  final UserId userId;

  /// The document the content belongs to.
  final DocumentId documentId;

  /// Identifies the version of the content (the `ETag` of the API).
  final String version;

  /// The content.
  final Uint8List bytes;
}

/// What [storeDocumentContent] needs.
@immutable
final class StoreDocumentContentDeps {
  /// Creates the dependencies of the storage of a download.
  const new({required this.files, required this.monitoring});

  /// Where the content is kept.
  final FileStore files;

  /// Where a failure is reported.
  final Monitoring monitoring;
}

/// Keeps a download: writes it whole or not at all to the file of its user,
/// document and version, and says where it is. Both repositories, the HTTP one
/// and the in-memory one, end their `fetchContent` here, so the two
/// configurations name and keep the files the same way. The same download again
/// replaces the file with what it has just fetched.
///
/// A file that cannot be written is `unexpected` for the caller, with a cause
/// that is a kind of failure and nothing else, and the monitoring is told with
/// the code the file system gave: never a path, a name or the title.
Future<Result<DocumentLocation, UnexpectedError>> storeDocumentContent(
  StoreDocumentContentDeps deps,
  DownloadedDocument download,
) async {
  final name = documentFileName(
    download.userId,
    download.documentId,
    download.version,
  );
  final written = await deps.files.write(name, download.bytes);
  if (written case Err(:final error)) {
    deps.monitoring.captureError(
      MonitoringEvent.documentContentNotStored,
      storageWriteFailed(error.cause),
      {
        LogAttribute.resource: _contentResource,
        LogAttribute.documentId: download.documentId,
      },
    );
    return err(unexpected(_notStoredCause));
  }

  final location = parseDocumentLocation(deps.files.uriOf(name));
  switch (location) {
    case Ok(:final value):
      return ok(value);
    case Err():
      return err(unexpected(_notStoredCause));
  }
}
