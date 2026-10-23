import 'dart:async';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/documents/application/ports/document_repository.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';

import 'copy_plain.dart';
import 'fake_network.dart';

/// The remote documents of a test: a document and the location of its content
/// go together.
class FakeDocumentRepository implements DocumentRepository {
  /// Creates a repository that goes down with [_network].
  new(this._network);

  final FakeNetwork _network;

  /// Makes every call fail with this error while set.
  RepositoryError? failure;

  /// Makes only `fetchContent` fail with this error while set: the metadata is
  /// still served.
  RepositoryError? contentFailure;

  /// Called when a request arrives, before the server answers: a test uses it
  /// to change the world while the request is in flight (another user signs
  /// in, say).
  FutureOr<void> Function()? onRequest;

  /// The id of every `get` call, in order.
  final List<DocumentId> getCalls = [];

  /// The id of every `fetchContent` call, in order.
  final List<DocumentId> fetchContentCalls = [];

  final Set<DocumentId> _forbiddenIds = {};
  final Map<DocumentId, ({Document document, DocumentLocation location})>
  _documents = {};

  /// Adds a document the server holds, with the location of its content.
  void addDocument(Document document, DocumentLocation location) {
    _documents[document.id] = (document: document, location: location);
  }

  /// The server has the document but refuses the caller: it answers
  /// `forbidden`.
  void forbid(DocumentId id) {
    _forbiddenIds.add(id);
  }

  @override
  Future<Result<Document, RepositoryError>> get(DocumentId id) async {
    getCalls.add(id);
    await onRequest?.call();
    final unavailable = _unavailable();
    if (unavailable != null) {
      return err(unavailable);
    }
    if (_forbiddenIds.contains(id)) {
      return err(forbidden());
    }
    final entry = _documents[id];
    if (entry == null) {
      return err(notFound());
    }
    return ok(copyPlain(entry.document));
  }

  @override
  Future<Result<DocumentLocation, RepositoryError>> fetchContent(
    DocumentId id,
  ) async {
    fetchContentCalls.add(id);
    await onRequest?.call();
    final unavailable = _unavailable() ?? contentFailure;
    if (unavailable != null) {
      return err(unavailable);
    }
    if (_forbiddenIds.contains(id)) {
      return err(forbidden());
    }
    final entry = _documents[id];
    if (entry == null) {
      return err(notFound());
    }
    return ok(entry.location);
  }

  RepositoryError? _unavailable() =>
      _network.online ? failure : networkUnavailable();
}
