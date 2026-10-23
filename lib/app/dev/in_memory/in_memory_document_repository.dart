import 'package:boardroom/app/dev/in_memory/in_memory_backend.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/features/documents/application/ports/document_repository.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:boardroom/features/documents/infrastructure/store_document_content.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';

/// The documents of the simulated server. Downloading the content is real in
/// everything but the network: the server makes a PDF for the document, and it
/// is written to the files of the device ([FileStore]) the way the HTTP
/// repository writes what it downloads, so the viewer opens a file in the mock
/// configuration as it does in the http one.
final class InMemoryDocumentRepository implements DocumentRepository {
  /// Creates the repository over `backend`, writing the downloads to `files`.
  /// `monitoring` is told when what was written cannot be used.
  const new(this._backend, this._files, this._monitoring);

  final InMemoryBackend _backend;
  final FileStore _files;
  final Monitoring _monitoring;

  @override
  Future<Result<Document, RepositoryError>> get(DocumentId id) =>
      _backend.getDocument(id);

  @override
  Future<Result<DocumentLocation, RepositoryError>> fetchContent(
    DocumentId id,
  ) async {
    final served = await _backend.fetchDocumentContent(id);
    switch (served) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        final stored = await storeDocumentContent(
          StoreDocumentContentDeps(files: _files, monitoring: _monitoring),
          DownloadedDocument(
            userId: value.userId,
            documentId: id,
            version: value.version,
            bytes: value.bytes,
          ),
        );
        switch (stored) {
          case Ok(:final value):
            return ok(value);
          case Err(:final error):
            return err(error);
        }
    }
  }
}
