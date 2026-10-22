import 'dart:async';

import 'package:boardroom/application/ports/document_repository.dart';
import 'package:boardroom/domain/entities/document.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/shared/validation.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import 'support.dart';

/// What the suite needs besides the port.
final class DocumentRepositoryHarness {
  /// Creates a harness.
  const new({
    required this.repository,
    required this.serve,
    required this.forbid,
    required this.signInAs,
    required this.setOnline,
    required this.refuseCaller,
  });

  /// The adapter under test.
  final DocumentRepository repository;

  /// Makes the server hold exactly these documents, all of them visible to the
  /// signed-in user, and forgets the ones it held.
  final FutureOr<void> Function(List<Document> documents) serve;

  /// Makes the server hold this document as one the signed-in user may not
  /// have.
  final FutureOr<void> Function(Document document) forbid;

  /// From now on the requests are authenticated as this user, who is allowed
  /// the documents that `serve` put on the server, like the first user.
  final FutureOr<void> Function(UserId userId) signInAs;

  /// Cuts and restores the connection.
  final void Function({required bool online}) setOnline;

  /// From now on the server refuses the caller: no valid credentials.
  final FutureOr<void> Function() refuseCaller;
}

/// What an implementation of the repository can be asked beyond what any can.
final class DocumentRepositoryContractOptions {
  /// Creates the options.
  const new({required this.downloadsPerUserAndVersion});

  /// Whether the adapter downloads a document once per user and per version, so
  /// that a location is never shared by two users nor kept across versions. The
  /// scripted server of the fakes, whose locations are given by the test,
  /// cannot.
  final bool downloadsPerUserAndVersion;
}

/// Makes a harness, now or later.
typedef DocumentRepositoryFactory =
    FutureOr<DocumentRepositoryHarness> Function();

final Document _internal = aDocument();
final Document _confidential = aConfidentialDocument(
  id: aDocumentId('document-2'),
  title: 'Remuneration report',
);
final DocumentId _unknown = aDocumentId('does-not-exist');

/// The contract of `DocumentRepository`, as a suite any implementation runs:
/// metadata by id, `notFound` for an unknown document, a location for the
/// content that can be asked for twice, and failures that are results.
void describeDocumentRepositoryContract(
  String name,
  DocumentRepositoryFactory createHarness,
  DocumentRepositoryContractOptions options,
) {
  group('$name honours the DocumentRepository contract', () {
    late DocumentRepositoryHarness harness;
    late DocumentRepository repository;

    setUp(() async {
      harness = await createHarness();
      repository = harness.repository;
      await harness.serve([_internal, _confidential]);
    });

    test('returns the metadata of a document', () async {
      expect(await repository.get(_internal.id), equals(ok(_internal)));
      expect(await repository.get(_confidential.id), equals(ok(_confidential)));
    });

    test('answers notFound for a document the server does not hold', () async {
      expect(await repository.get(_unknown), equals(err(notFound())));
      expect(await repository.fetchContent(_unknown), equals(err(notFound())));
    });

    test('makes the content readable and says where', () async {
      final location = valueOf(await repository.fetchContent(_internal.id));

      expect(location, isA<String>());
      expect(trimText(location), isNot(equals('')));
    });

    test('gives each document its own location', () async {
      final first = valueOf(await repository.fetchContent(_internal.id));
      final second = valueOf(await repository.fetchContent(_confidential.id));

      expect(first, isNot(equals(second)));
    });

    test('can be asked for the content of the same document twice, '
        'and says where both times', () async {
      final first = await repository.fetchContent(_internal.id);
      final second = await repository.fetchContent(_internal.id);

      expect(isOk(first), isTrue);
      expect(second, equals(first));
    });

    test('refuses a document the user may not have with forbidden, '
        'for the metadata and for the content', () async {
      final hidden = aConfidentialDocument(
        id: aDocumentId('hidden'),
        title: 'Restricted',
      );
      await harness.forbid(hidden);

      expect(await repository.get(hidden.id), equals(err(forbidden())));
      expect(
        await repository.fetchContent(hidden.id),
        equals(err(forbidden())),
      );
      expect(isOk(await repository.get(_internal.id)), isTrue);
    });

    // An adapter that cannot download once per user and version skips these:
    // they show as skipped.
    group('the downloads', () {
      test('gives two users two locations: '
          'a download is never reused for somebody else', () async {
        final first = valueOf(await repository.fetchContent(_internal.id));

        await harness.signInAs(aUserId('user-2'));
        final second = valueOf(await repository.fetchContent(_internal.id));

        expect(second, isNot(equals(first)));
      });

      test('gives the same user the same location '
          'for the same version of a document', () async {
        final first = valueOf(await repository.fetchContent(_internal.id));
        final second = valueOf(await repository.fetchContent(_internal.id));

        expect(second, equals(first));
      });

      test('gives a new version of a document a new location: '
          'a download is never reused across versions', () async {
        final first = valueOf(await repository.fetchContent(_internal.id));

        await harness.serve([
          _internal.copyWith(pageCount: _internal.pageCount + 1),
          _confidential,
        ]);
        final second = valueOf(await repository.fetchContent(_internal.id));

        expect(second, isNot(equals(first)));
      });
    }, skip: !options.downloadsPerUserAndVersion);

    test('answers networkUnavailable without a connection, '
        'and recovers with it', () async {
      harness.setOnline(online: false);

      expect(
        await repository.get(_internal.id),
        equals(err(networkUnavailable())),
      );
      expect(
        await repository.fetchContent(_internal.id),
        equals(err(networkUnavailable())),
      );

      harness.setOnline(online: true);
      expect(isOk(await repository.get(_internal.id)), isTrue);
      expect(isOk(await repository.fetchContent(_internal.id)), isTrue);
    });

    test('answers unauthorized when the caller is refused', () async {
      await harness.refuseCaller();

      expect(await repository.get(_internal.id), equals(err(unauthorized())));
      expect(
        await repository.fetchContent(_internal.id),
        equals(err(unauthorized())),
      );
    });
  });
}
