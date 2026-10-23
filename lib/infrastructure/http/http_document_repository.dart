import 'package:boardroom/application/ports/document_repository.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/entities/document.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/document_location.dart';
import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/infrastructure/documents/store_document_content.dart';
import 'package:boardroom/infrastructure/files/file_store.dart';
import 'package:boardroom/infrastructure/http/dto/document_dto.dart';
import 'package:boardroom/infrastructure/http/dto/wire.dart';
import 'package:boardroom/infrastructure/http/gateway_errors.dart';
import 'package:boardroom/infrastructure/http/http_client.dart';
import 'package:boardroom/infrastructure/http/invalid_response.dart';
import 'package:boardroom/infrastructure/http/protocol.dart';
import 'package:boardroom/infrastructure/http/well_formed.dart';
import 'package:boardroom/infrastructure/pdf/pdf_signature.dart';
import 'package:meta/meta.dart';

// A version is the `ETag` of the answer: visible ASCII, and short. It is only
// ever hashed.
final RegExp _versionFormat = RegExp(r'^[\x21-\x7e]{1,256}$');

/// What `HttpDocumentRepository` can be told.
@immutable
final class HttpDocumentRepositoryOptions {
  /// Creates the options.
  const new({this.maxContentBytes = maxDocumentBytes, this.downloadTimeout});

  /// The most a document may weigh. Defaults to `maxDocumentBytes`.
  final int maxContentBytes;

  /// How long a download may take. Defaults to the timeout of the client.
  final DurationMillis? downloadTimeout;
}

/// The documents of the API: `GET /documents/{id}` for the metadata, and
/// `GET /documents/{id}/content` for the file. The metadata must be those of
/// the document that was asked for: an answer about another one is
/// `unexpected`. The requests are given to the client as functions, so that the
/// route, which is made of an identifier, is built where the client can catch a
/// failure: an adapter never throws.
///
/// **Downloading.** `fetchContent` fetches the PDF through the client, which
/// gives it the rules of every other request (the token of the signed-in user
/// read when the request is created, the statuses, the redirects refused, no
/// URL in a cause) and adds its own limits: the answer must be
/// `application/pdf` and at most `maxContentBytes`, and it has its own timeout.
/// Then:
///
/// - the bytes must start with `%PDF-`. A server that says `application/pdf`
///   and sends something else (an error page, a sign-in form) is not trusted:
///   nothing is stored and the answer is `unexpected`;
/// - the answer must carry an `ETag`, the version of the content. The file is
///   named for the user the token belongs to, the document and the version (see
///   `documentFileName`), so a download is never reused for somebody else nor
///   across versions, and a document that changed is a new file;
/// - the file is written whole or not at all (`FileStore.write`), and the
///   location of the file is what `fetchContent` answers. Asking again
///   downloads again, and replaces the file.
///
/// Reading from the cache when the network is down is not this adapter's
/// business: that is the offline policy of the use cases, which keep the
/// location.
final class HttpDocumentRepository implements DocumentRepository {
  /// Creates the repository over `client`, writing the files to `files`.
  const new(
    this._client,
    this._monitoring,
    this._files, [
    this._options = const HttpDocumentRepositoryOptions(),
  ]);

  final HttpClient _client;
  final Monitoring _monitoring;
  final FileStore _files;
  final HttpDocumentRepositoryOptions _options;

  @override
  Future<Result<Document, RepositoryError>> get(DocumentId id) async {
    final answer = await _client.request(
      () => HttpRequestSpec<DocumentWire>(
        method: HttpMethod.get,
        path: Routes.document(requireWellFormed(id)),
        resource: HttpResource.document,
        decode: (json) => decodeWire(json, DocumentWire.fromJson),
      ),
    );
    final DocumentWire wire;
    switch (answer) {
      case Err(:final error):
        return err(asRepositoryError(error));
      case Ok(:final value):
        wire = value;
    }

    final Document document;
    switch (toDocument(wire)) {
      case Err(:final error):
        return err(domainViolation(_monitoring, HttpResource.document, error));
      case Ok(:final value):
        document = value;
    }
    if (document.id != id) {
      return err(
        identityViolation(
          _monitoring,
          HttpResource.document,
          IdentityViolation.otherItem,
        ),
      );
    }
    return ok(document);
  }

  @override
  Future<Result<DocumentLocation, RepositoryError>> fetchContent(
    DocumentId id,
  ) async {
    final HttpDocumentRepositoryOptions(:maxContentBytes, :downloadTimeout) =
        _options;
    final answer = await _client.download(
      () => HttpDownloadSpec(
        method: HttpMethod.get,
        path: Routes.documentContent(requireWellFormed(id)),
        resource: HttpResource.documentContent,
        mediaType: mediaTypePdf,
        maxBytes: maxContentBytes,
        timeout: downloadTimeout,
      ),
    );
    final Downloaded downloaded;
    switch (answer) {
      case Err(:final error):
        return err(asRepositoryError(error));
      case Ok(:final value):
        downloaded = value;
    }

    final Downloaded(:bytes, :etag, :userId) = downloaded;
    if (!hasPdfSignature(bytes)) {
      return err(
        contentViolation(
          _monitoring,
          HttpResource.documentContent,
          ContentViolation.wrongSignature,
        ),
      );
    }
    if (etag == null || !_versionFormat.hasMatch(etag)) {
      return err(
        contentViolation(
          _monitoring,
          HttpResource.documentContent,
          ContentViolation.noVersion,
        ),
      );
    }

    final stored = await storeDocumentContent(
      StoreDocumentContentDeps(files: _files, monitoring: _monitoring),
      DownloadedDocument(
        userId: userId,
        documentId: id,
        version: etag,
        bytes: bytes,
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
