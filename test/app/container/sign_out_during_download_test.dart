import 'dart:async';
import 'dart:typed_data';

import 'package:boardroom/app/composition/ports.dart';
import 'package:boardroom/app/composition/use_cases.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/documents/application/ports/document_repository.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:boardroom/features/documents/infrastructure/drift_document_cache.dart';
import 'package:boardroom/features/documents/infrastructure/store_document_content.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/builders/builders.dart';
import '../../support/fakes/create_fakes.dart';
import '../../support/infrastructure/document_device.dart';
import '../../support/infrastructure/test_database.dart';
import '../../support/infrastructure/test_files.dart';

// The scenario of `signOutDuringDownload.test.ts`: a download that is still
// running when the user signs out. The repository writes the file as soon as
// the bytes have arrived, the use case finds out afterwards that nobody is
// signed in, and no database row ever points at the file: the sweep of orphans
// only runs when the container starts, so the use case itself must leave
// nothing behind. Real cache (SQLite) and real files, wired like the app.

final Uint8List _pdfBytes = Uint8List.fromList([
  0x25,
  0x50,
  0x44,
  0x46,
  0x2d,
  1,
  2,
  3,
]);

/// A repository whose download waits for the test to let it finish.
final class _SlowDocuments implements DocumentRepository {
  new({
    required this.document,
    required this.store,
    required this.userId,
    required this.started,
    required this.release,
  });

  final Document document;
  final Future<Result<DocumentLocation, AppError>> Function(
    DocumentId id,
    UserId userId,
  )
  store;
  final UserId userId;
  final Completer<void> started;
  final Future<void> release;

  @override
  Future<Result<Document, RepositoryError>> get(DocumentId id) async =>
      ok(document);

  @override
  Future<Result<DocumentLocation, RepositoryError>> fetchContent(
    DocumentId id,
  ) async {
    started.complete();
    await release;
    final stored = await store(id, userId);
    switch (stored) {
      case Ok(:final value):
        return ok(value);
      case Err(:final error):
        return err(error as RepositoryError);
    }
  }
}

void main() {
  final databases = temporaryDirectory();
  final filesParent = temporaryDirectory();

  group('a document that finishes downloading after the user signed out', () {
    test('leaves no file on the device', () async {
      final fakes = createFakes();
      final test = await openTestDatabase(databases);
      final device = aDocumentDevice(filesParent, realLocations: true);
      final documentCache = DriftDocumentCache(
        DriftDocumentCacheOptions(
          database: test.database,
          files: device.store,
          monitoring: fakes.monitoring,
        ),
      );
      final document = aConfidentialDocument();
      final userId = switch (await fakes.auth.current()) {
        Ok(value: final session?) => session.user.id,
        _ => throw StateError('Nobody is signed in.'),
      };

      final started = Completer<void>();
      final release = Completer<void>();
      final documents = _SlowDocuments(
        document: document,
        userId: userId,
        started: started,
        release: release.future,
        store: (id, owner) => storeDocumentContent(
          StoreDocumentContentDeps(
            files: device.store,
            monitoring: fakes.monitoring,
          ),
          DownloadedDocument(
            userId: owner,
            documentId: id,
            version: 'v1',
            bytes: _pdfBytes,
          ),
        ),
      );
      final useCases = wireUseCases(
        Ports(
          clock: fakes.clock,
          monitoring: fakes.monitoring,
          auth: fakes.auth,
          biometricGate: fakes.biometricGate,
          connectivity: fakes.connectivity,
          screenProtection: fakes.screenProtection,
          meetings: fakes.meetings,
          meetingCache: fakes.meetingCache,
          documents: documents,
          documentCache: documentCache,
          votes: fakes.votes,
          outbox: fakes.outbox,
        ),
        UseCaseSettings(
          maxCacheAge: fakes.maxCacheAge,
          maxAttempts: fakes.maxAttempts,
          gracePeriod: aDuration(millisPerMinute),
          startsLocked: false,
        ),
      );

      final opening = useCases.openDocument.execute(documentId: document.id);
      await started.future;
      await useCases.signOut.execute();
      release.complete();
      final opened = await opening;

      expect(opened, isA<Err<Object?, AppError>>());
      expect(await device.store.list(), equals(ok(<String>[])));
    });
  });
}
