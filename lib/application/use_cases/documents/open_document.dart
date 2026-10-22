import 'package:boardroom/application/ports/document_cache.dart';
import 'package:boardroom/application/ports/document_repository.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/shared/cache_resource.dart';
import 'package:boardroom/application/shared/load_with_cache_fallback.dart';
import 'package:boardroom/application/shared/loaded.dart';
import 'package:boardroom/application/shared/require_session.dart';
import 'package:boardroom/application/shared/screen_protection_coordinator.dart';
import 'package:boardroom/domain/entities/document.dart';
import 'package:boardroom/domain/entities/session.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/document_location.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/watermark.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'open_document.freezed.dart';

/// What [OpenDocument] needs, on top of what the cache fallback needs.
abstract interface class OpenDocumentDeps implements CacheFallbackDeps {
  /// The remote documents.
  DocumentRepository get documents;

  /// The local cache of documents.
  @override
  DocumentCache get documentCache;

  /// The instance shared with `CloseDocument`.
  ScreenProtectionCoordinator get screenProtectionCoordinator;
}

/// Everything the viewer needs to show a document.
@freezed
abstract class OpenedDocument with _$OpenedDocument {
  /// Creates the answer of [OpenDocument].
  const factory({
    required Document document,
    required DocumentLocation location,

    /// To be drawn over the content. See [Watermark] for what is decided where.
    required Watermark watermark,

    /// Fresh from the server, or the copy already viewed (stale) when there is
    /// no network.
    required DataSource source,

    /// True when the screen is protected against capture: always the case for a
    /// confidential document, and for any document served from the cache,
    /// whatever level the cache remembers.
    required bool screenProtected,
  }) = _OpenedDocument;
}

/// What opening a document fails with: a [SessionRequiredError], a
/// [SessionChangedError], a [RepositoryError] or a [ScreenProtectionError].
typedef OpenDocumentError = AppError;

/// Opens a document for reading. Requires a valid session, whose user owns the
/// cached copy. Steps:
///
/// 1. loads the metadata and the content location with the offline policy of
///    [loadWithCacheFallback] (a document already viewed opens without
///    network). The metadata and the content come together, from the server or
///    from the cache: if any part of what is returned came from the cache, the
///    whole is stale;
/// 2. checks again that the user who asked is still the one signed in, and the
///    app unlocked, because the load can take long. Otherwise the answer is
///    `sessionChanged` and nothing is protected or returned: the content of one
///    user must never come back under another's name. The watermark is built
///    from the session of this check;
/// 3. turns the screen protection on when the document is confidential OR
///    served from the cache, through the coordinator that remembers which views
///    are open. A copy in the cache can be older than the last change of the
///    classification of the document (it may have been public when it was
///    saved), so what the cache says about the level is not trusted. This fails
///    closed: if the protection cannot be enabled, the document is NOT returned
///    and the error is, so the viewer never has a location it could show
///    unprotected;
/// 4. logs the access.
///
/// The screen calls `CloseDocument` with the id of the document when it leaves
/// it.
final class OpenDocument {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final OpenDocumentDeps _deps;

  /// Opens the document [documentId].
  Future<Result<OpenedDocument, OpenDocumentError>> execute({
    required DocumentId documentId,
  }) async {
    final OpenDocumentDeps(:clock, :monitoring, :screenProtectionCoordinator) =
        _deps;

    final UserId owner;
    switch (await requireSession(_deps)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        owner = value.user.id;
    }

    final Loaded<ViewableDocument> loaded;
    switch (await _load(owner, documentId)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        loaded = value;
    }
    final ViewableDocument(:document, :location) = loaded.data;

    final Session reader;
    switch (await requireSameUser(_deps, owner)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        reader = value;
    }

    final screenProtected =
        isConfidential(document) || loaded.source.freshness == Freshness.stale;
    if (screenProtected) {
      final enabled = await screenProtectionCoordinator.acquire(document.id);
      if (enabled case Err(:final error)) {
        return err(error);
      }
    }

    monitoring.log(LogLevel.info, MonitoringEvent.documentOpened, {
      LogAttribute.documentId: document.id,
      LogAttribute.userId: reader.user.id,
      LogAttribute.confidentiality: document.confidentiality.value,
      LogAttribute.freshness: loaded.source.freshness.value,
    });

    return ok(
      OpenedDocument(
        document: document,
        location: location,
        watermark: createWatermark(reader.user, clock.now()),
        source: loaded.source,
        screenProtected: screenProtected,
      ),
    );
  }

  Future<Result<Loaded<ViewableDocument>, AppError>> _load(
    UserId owner,
    DocumentId documentId,
  ) {
    final OpenDocumentDeps(:documents, :documentCache) = _deps;

    return loadWithCacheFallback<ViewableDocument, RepositoryError>(
      _deps,
      owner,
      CacheFallbackSource(
        resource: CacheResource.document,
        attributes: {LogAttribute.documentId: documentId},
        fetch: () async {
          final Document document;
          switch (await documents.get(documentId)) {
            case Err(:final error):
              return err(error);
            case Ok(:final value):
              document = value;
          }
          switch (await documents.fetchContent(documentId)) {
            case Err(:final error):
              return err(error);
            case Ok(:final value):
              return ok(ViewableDocument(document: document, location: value));
          }
        },
        save: (viewable, cachedAt) =>
            documentCache.save(owner, viewable, cachedAt),
        read: () => documentCache.read(owner, documentId),
        remove: () => documentCache.remove(owner, documentId),
        revoke: () => documentCache.remove(owner, documentId),
      ),
    );
  }
}
