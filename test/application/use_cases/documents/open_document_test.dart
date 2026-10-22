import 'package:boardroom/application/ports/document_cache.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/ports/types/cache_entry.dart';
import 'package:boardroom/application/shared/cache_resource.dart';
import 'package:boardroom/application/shared/loaded.dart';
import 'package:boardroom/application/use_cases/auth/sign_out.dart';
import 'package:boardroom/application/use_cases/documents/close_document.dart';
import 'package:boardroom/application/use_cases/documents/open_document.dart';
import 'package:boardroom/domain/entities/document.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/document_location.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/watermark.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import '../../support/create_fakes.dart';
import '../../support/fake_monitoring.dart';

typedef _Opened = Ok<OpenedDocument, OpenDocumentError>;

final Document _confidential = aConfidentialDocument();
final Document _internal = aDocument(
  id: aDocumentId('document-2'),
  // The level of the document is the point of the tests, so it is spelled out
  // although the builder happens to default to it.
  // ignore: avoid_redundant_argument_values
  confidentiality: ConfidentialityLevel.internal,
);
final DocumentLocation _location = aDocumentLocation(
  'file:///private/document-1.pdf',
);
final LogAttributes _documentAttributes = {
  LogAttribute.documentId: aDocumentId(),
  LogAttribute.resource: CacheResource.document.value,
};
final DocumentLocation _otherLocation = aDocumentLocation(
  'file:///private/document-2.pdf',
);

({Fakes fakes, OpenDocument useCase}) _setup() {
  final fakes = createFakes();
  fakes.documents.addDocument(_confidential, _location);
  fakes.documents.addDocument(_internal, _otherLocation);
  return (fakes: fakes, useCase: OpenDocument(fakes));
}

Future<Result<OpenedDocument, OpenDocumentError>> _open(
  OpenDocument useCase,
  DocumentId documentId,
) => useCase.execute(documentId: documentId);

void main() {
  group('OpenDocument', () {
    group('a user who is not the one who viewed the document', () {
      test('finds nothing of it offline: A views a confidential document, B '
          'signs in on the device', () async {
        final (:fakes, :useCase) = _setup();
        await _open(useCase, _confidential.id);
        await fakes.screenProtection.disable();
        fakes.auth.session = aSession(
          user: aUser(id: aUserId('user-B'), email: anEmail('b@example.com')),
        );
        fakes.network.goOffline();

        expect(
          await _open(useCase, _confidential.id),
          equals(err(networkUnavailable())),
        );
        expect(fakes.screenProtection.enabled, isFalse);
      });

      test('finds nothing of it after the sign-out of A either: the cache was '
          'emptied', () async {
        final (:fakes, :useCase) = _setup();
        await _open(useCase, _confidential.id);
        await SignOut(fakes).execute();
        fakes.auth.session = aSession();
        fakes.appLock.unlock();
        fakes.network.goOffline();

        expect(
          await _open(useCase, _confidential.id),
          equals(err(networkUnavailable())),
        );
        expect(fakes.documentCache.isEmpty(), isTrue);
      });
    });

    group('a confidential document', () {
      test('turns the screen protection on before returning the '
          'document', () async {
        final (:fakes, :useCase) = _setup();

        final result = await _open(useCase, _confidential.id);

        expect(
          result,
          equals(
            ok(
              OpenedDocument(
                document: _confidential,
                location: _location,
                watermark: Watermark(
                  fullName: aUser().fullName,
                  email: aUser().email,
                  viewedAt: now,
                ),
                source: const DataSource.fresh(),
                screenProtected: true,
              ),
            ),
          ),
        );
        expect(fakes.screenProtection.enabled, isTrue);
      });

      test('fails closed: without protection, the document is not '
          'returned', () async {
        final (:fakes, :useCase) = _setup();
        fakes.screenProtection.enableFailure = screenProtectionUnsupported();

        final result = await _open(useCase, _confidential.id);

        expect(result, equals(err(screenProtectionUnsupported())));
        expect(fakes.screenProtection.enabled, isFalse);
        expect(
          fakes.monitoring.loggedEvents(),
          isNot(contains(MonitoringEvent.documentOpened)),
        );
      });

      test('reports a protection that failed to start', () async {
        final (:fakes, :useCase) = _setup();
        fakes.screenProtection.enableFailure = screenProtectionFailed();

        expect(
          await _open(useCase, _confidential.id),
          equals(err(screenProtectionFailed())),
        );
      });
    });

    group('several confidential documents', () {
      final second = aConfidentialDocument(id: aDocumentId('document-3'));

      test('keeps the screen protected until the last one is '
          'closed', () async {
        final (:fakes, :useCase) = _setup();
        fakes.documents.addDocument(
          second,
          aDocumentLocation('file:///private/document-3.pdf'),
        );
        final close = CloseDocument(fakes);
        await _open(useCase, _confidential.id);
        await _open(useCase, second.id);

        await close.execute(documentId: second.id);
        expect(fakes.screenProtection.enabled, isTrue);

        await close.execute(documentId: _confidential.id);
        expect(fakes.screenProtection.enabled, isFalse);
      });

      test('does not register a document that could not be '
          'protected', () async {
        final (:fakes, :useCase) = _setup();
        fakes.documents.addDocument(
          second,
          aDocumentLocation('file:///private/document-3.pdf'),
        );
        fakes.screenProtection.enableFailure = screenProtectionFailed();
        await _open(useCase, _confidential.id);
        fakes.screenProtection.enableFailure = null;
        await _open(useCase, second.id);

        await CloseDocument(fakes).execute(documentId: second.id);

        expect(fakes.screenProtection.enabled, isFalse);
      });
    });

    group('a document that is not confidential', () {
      test('is shown without turning the protection on', () async {
        final (:fakes, :useCase) = _setup();

        final result = await _open(useCase, _internal.id);

        expect(
          result,
          isA<_Opened>().having(
            (r) => r.value.screenProtected,
            'screenProtected',
            isFalse,
          ),
        );
        expect(fakes.screenProtection.enableCalls, equals(0));
      });

      test('is not blocked by a platform that cannot protect the '
          'screen', () async {
        final (:fakes, :useCase) = _setup();
        fakes.screenProtection.enableFailure = screenProtectionUnsupported();

        final result = await _open(useCase, _internal.id);

        expect(
          result,
          isA<_Opened>().having(
            (r) => r.value.document,
            'document',
            equals(_internal),
          ),
        );
        expect(
          result,
          isA<_Opened>().having(
            (r) => r.value.screenProtected,
            'screenProtected',
            isFalse,
          ),
        );
      });
    });

    group('the watermark', () {
      test('is built from the signed-in user and the instant of the '
          'clock', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.session = aSession(user: aUser(fullName: 'Bruno Durand'));
        fakes.clock.set(at(5000));

        final result = await _open(useCase, _confidential.id);

        expect(
          result,
          isA<_Opened>().having(
            (r) => r.value.watermark,
            'watermark',
            equals(
              Watermark(
                fullName: 'Bruno Durand',
                email: aUser().email,
                viewedAt: at(5000),
              ),
            ),
          ),
        );
      });
    });

    group('the session', () {
      test('is required', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.session = null;

        expect(
          await _open(useCase, _confidential.id),
          equals(err(notAuthenticated())),
        );
        expect(fakes.documents.getCalls, isEmpty);
        expect(fakes.screenProtection.enableCalls, equals(0));
      });

      test('must not have expired', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.session = aSession(expiresAt: now);

        expect(
          await _open(useCase, _confidential.id),
          equals(err(sessionExpired())),
        );
        expect(fakes.documents.getCalls, isEmpty);
      });
    });

    group('the access log', () {
      test('records who opened which document, with identifiers '
          'only', () async {
        final (:fakes, :useCase) = _setup();

        await _open(useCase, _confidential.id);

        expect(
          fakes.monitoring.logs,
          equals([
            LogRecord(
              level: LogLevel.info,
              event: MonitoringEvent.documentOpened,
              attributes: {
                LogAttribute.documentId: _confidential.id,
                LogAttribute.userId: aUser().id,
                LogAttribute.confidentiality:
                    ConfidentialityLevel.confidential.value,
                LogAttribute.freshness: Freshness.fresh.value,
              },
            ),
          ]),
        );
        final serialised = fakes.monitoring.logs.toString();
        expect(serialised, isNot(contains(aUser().fullName)));
        expect(serialised, isNot(contains(aUser().email)));
      });
    });

    group('the offline policy', () {
      test('caches the metadata and the location of a document it '
          'opened', () async {
        final (:fakes, :useCase) = _setup();
        await _open(useCase, _confidential.id);

        expect(
          await fakes.documentCache.read(aUserId(), _confidential.id),
          equals(
            ok(
              CacheEntry(
                value: ViewableDocument(
                  document: _confidential,
                  location: _location,
                ),
                cachedAt: now,
              ),
            ),
          ),
        );
      });

      test('opens a document already viewed without network, flagged stale, '
          'still protected', () async {
        final (:fakes, :useCase) = _setup();
        await _open(useCase, _confidential.id);
        await fakes.screenProtection.disable();
        fakes.network.goOffline();
        fakes.clock.advance(1800000);

        final result = await _open(useCase, _confidential.id);

        expect(
          result,
          isA<_Opened>().having(
            (r) => r.value.source,
            'source',
            equals(DataSource.stale(cachedAt: now)),
          ),
        );
        expect(
          result,
          isA<_Opened>().having(
            (r) => r.value.location,
            'location',
            equals(_location),
          ),
        );
        expect(
          result,
          isA<_Opened>().having(
            (r) => r.value.watermark.viewedAt,
            'watermark.viewedAt',
            equals(at(1800000)),
          ),
        );
        expect(fakes.screenProtection.enabled, isTrue);
      });

      test('returns the network error for a document never viewed', () async {
        final (:fakes, :useCase) = _setup();
        fakes.network.goOffline();

        expect(
          await _open(useCase, _confidential.id),
          equals(err(networkUnavailable())),
        );
        expect(fakes.screenProtection.enableCalls, equals(0));
      });

      test('does not cache, nor protect, nor return a document whose content '
          'could not be fetched', () async {
        final (:fakes, :useCase) = _setup();
        fakes.documents.contentFailure = unauthorized();

        expect(
          await _open(useCase, _confidential.id),
          equals(err(unauthorized())),
        );
        expect(fakes.documents.getCalls, equals([_confidential.id]));
        expect(
          await fakes.documentCache.read(aUserId(), _confidential.id),
          equals(ok<CacheEntry<ViewableDocument>?>(null)),
        );
        expect(fakes.screenProtection.enableCalls, equals(0));
      });

      test('returns notFound for an unknown document', () async {
        final (:fakes, :useCase) = _setup();

        expect(
          await _open(useCase, aDocumentId('unknown')),
          equals(err(notFound())),
        );
        expect(fakes.documents.fetchContentCalls, isEmpty);
      });

      test('fetches the content only after the metadata is known', () async {
        final (:fakes, :useCase) = _setup();

        await _open(useCase, _confidential.id);
        await _open(useCase, aDocumentId('unknown'));

        expect(
          fakes.documents.getCalls,
          equals([_confidential.id, aDocumentId('unknown')]),
        );
        expect(fakes.documents.fetchContentCalls, equals([_confidential.id]));
      });

      test('evicts the cached copy when the server refuses, and never serves '
          'it afterwards', () async {
        final (:fakes, :useCase) = _setup();
        await _open(useCase, _confidential.id);
        await fakes.screenProtection.disable();
        fakes.documents.failure = unauthorized();

        final result = await _open(useCase, _confidential.id);

        expect(result, equals(err(unauthorized())));
        expect(isErr(result), isTrue);
        expect(fakes.screenProtection.enabled, isFalse);
        expect(
          await fakes.documentCache.read(aUserId(), _confidential.id),
          equals(ok<CacheEntry<ViewableDocument>?>(null)),
        );

        fakes.documents.failure = null;
        // The refused session is over: the user signs in again, and finds no
        // saved copy.
        fakes.auth.session = aSession();
        fakes.appLock.unlock();
        fakes.network.goOffline();
        expect(
          await _open(useCase, _confidential.id),
          equals(err(networkUnavailable())),
        );
      });

      test('evicts the cached copy of a document that no longer '
          'exists', () async {
        final (:fakes, :useCase) = _setup();
        await _open(useCase, _confidential.id);
        fakes.documents.failure = notFound();

        expect(await _open(useCase, _confidential.id), equals(err(notFound())));
        expect(
          await fakes.documentCache.read(aUserId(), _confidential.id),
          equals(ok<CacheEntry<ViewableDocument>?>(null)),
        );
      });

      test('refuses a cached copy older than the maximum age', () async {
        final (:fakes, :useCase) = _setup();
        fakes.auth.session = aSession(expiresAt: at(30 * millisPerDay));
        await _open(useCase, _confidential.id);
        fakes.network.goOffline();

        fakes.clock.advance(7 * millisPerDay);
        final atTheLimit = await _open(useCase, _confidential.id);
        expect(
          atTheLimit,
          isA<_Opened>().having(
            (r) => r.value.source,
            'source',
            equals(DataSource.stale(cachedAt: now)),
          ),
        );
        fakes.clock.advance(1);
        expect(
          await _open(useCase, _confidential.id),
          equals(err(networkUnavailable())),
        );
      });

      test('opens the document when the cache cannot be written, and captures '
          'the failure', () async {
        final (:fakes, :useCase) = _setup();
        fakes.documentCache.writeFailure = storageWriteFailed();

        final result = await _open(useCase, _confidential.id);

        expect(
          result,
          isA<_Opened>()
              .having((r) => r.value.document, 'document', _confidential)
              .having((r) => r.value.location, 'location', _location)
              .having(
                (r) => r.value.source,
                'source',
                const DataSource.fresh(),
              ),
        );
        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.cacheWriteFailed,
              error: storageWriteFailed(),
              attributes: _documentAttributes,
            ),
          ]),
        );
      });

      test('returns the network error, and captures the failure, when the '
          'cache cannot be read either', () async {
        final (:fakes, :useCase) = _setup();
        await _open(useCase, _confidential.id);
        await fakes.screenProtection.disable();
        fakes.network.goOffline();
        fakes.documentCache.readFailure = storageReadFailed();

        expect(
          await _open(useCase, _confidential.id),
          equals(err(networkUnavailable())),
        );
        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.cacheReadFailed,
              error: storageReadFailed(),
              attributes: _documentAttributes,
            ),
          ]),
        );
        expect(fakes.screenProtection.enableCalls, equals(1));
        expect(fakes.screenProtection.enabled, isFalse);
      });

      test('captures an eviction that failed, empties the caches, and still '
          'returns the refusal', () async {
        final (:fakes, :useCase) = _setup();
        await _open(useCase, _confidential.id);
        fakes.documents.forbid(_confidential.id);
        fakes.documentCache.removeFailure = storageWriteFailed();

        expect(
          await _open(useCase, _confidential.id),
          equals(err(forbidden())),
        );
        expect(fakes.documentCache.isEmpty(), isTrue);
        expect(
          fakes.monitoring.errors,
          equals([
            ErrorRecord(
              event: MonitoringEvent.cacheRemoveFailed,
              error: storageWriteFailed(),
              attributes: _documentAttributes,
            ),
          ]),
        );
      });

      test('logs that a cached document was served, with its id', () async {
        final (:fakes, :useCase) = _setup();
        await _open(useCase, _confidential.id);
        fakes.network.goOffline();
        fakes.monitoring.logs.clear();

        await _open(useCase, _confidential.id);

        expect(
          fakes.monitoring.logs.first,
          equals(
            LogRecord(
              level: LogLevel.info,
              event: MonitoringEvent.servedFromCache,
              attributes: _documentAttributes,
            ),
          ),
        );
      });
    });
  });
}
