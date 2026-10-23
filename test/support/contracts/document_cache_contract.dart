import 'dart:async';
import 'dart:convert';

import 'package:boardroom/core/application/ports/types/cache_entry.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:test/test.dart';

import '../builders/builders.dart';
import 'support.dart';

/// The files of the device, as far as the contract needs them. Content lives
/// outside the cache, at a location the repository produced, so a test must be
/// able to put some there, to see whether it is still there, and to lose it
/// behind the cache's back (the file was deleted, the storage was cleared). An
/// adapter that keeps no files cannot offer this, and the checks about content
/// are skipped for it (`keepsFiles: false`).
final class DocumentFiles {
  /// Creates the files of a device.
  const new({
    required this.put,
    required this.exists,
    required this.lose,
    required this.breakDeletion,
    required this.repairDeletion,
  });

  /// Puts content at the location, as a download would.
  final FutureOr<void> Function(DocumentLocation location) put;

  /// Whether there is content at the location.
  final FutureOr<bool> Function(DocumentLocation location) exists;

  /// Removes the content without telling the cache.
  final FutureOr<void> Function(DocumentLocation location) lose;

  /// From now on a file cannot be deleted (a locked file, a failing disk).
  final void Function() breakDeletion;

  /// Lets a file be deleted again.
  final void Function() repairDeletion;
}

/// What the suite needs besides the port.
final class DocumentCacheHarness {
  /// Creates a harness.
  const new({
    required this.cache,
    required this.breakWrites,
    required this.repairWrites,
    this.files,
    this.failNextStatement,
    this.reopen,
  });

  /// The adapter under test.
  final DocumentCache cache;

  /// The files of the device, for an adapter that keeps files.
  final DocumentFiles? files;

  /// From now on every `save` fails with a storage error.
  final void Function() breakWrites;

  /// Lets the store write again.
  final void Function() repairWrites;

  /// Makes the next statement the store sends to its storage fail, once. Only a
  /// store that has a storage to fail provides it
  /// (`StoreContractOptions.failsStatements`).
  final void Function()? failNextStatement;

  /// Closes the store and opens it again on the same storage and the same
  /// files, as a new start of the app would, and returns the new one. Only a
  /// store whose content survives provides it
  /// (`StoreContractOptions.survivesReopen`).
  final Future<DocumentCache> Function()? reopen;
}

/// What the suite needs to know of an implementation: its files, and the
/// storage it keeps them in.
final class DocumentCacheContractOptions extends StoreContractOptions {
  /// Creates the options.
  const new({
    required super.failsStatements,
    required super.survivesReopen,
    required this.keepsFiles,
  });

  /// Whether the adapter keeps files, so that the checks on the content can
  /// run.
  final bool keepsFiles;
}

/// Makes a harness, now or later.
typedef DocumentCacheFactory = FutureOr<DocumentCacheHarness> Function();

final UserId _owner = aUserId('owner-1');
final UserId _otherOwner = aUserId('owner-2');

/// A text as the hexadecimal digits of its UTF-16 code units: one name per
/// text, whatever it contains, in characters that every file system keeps apart
/// (no separator, and no letter whose case could make two names one). The
/// locations of the suite are file names in the directory a real store keeps
/// its files in.
String _hexOf(String text) =>
    text.codeUnits.map((unit) => unit.toRadixString(16).padLeft(4, '0')).join();

final _viewable = ViewableDocument(
  document: aDocument(),
  location: aDocumentLocation(),
);
final _otherViewable = ViewableDocument(
  document: aConfidentialDocument(
    id: aDocumentId('document-2'),
    title: 'Remuneration report',
  ),
  location: aDocumentLocation('file:///documents/document-2.pdf'),
);

/// What a cache answers for a document it holds.
Ok<CacheEntry<ViewableDocument>, Never> _entry(
  ViewableDocument viewable,
  int cachedAt,
) => ok(CacheEntry<ViewableDocument>(value: viewable, cachedAt: at(cachedAt)));

/// What a cache answers for a document it does not hold.
final Ok<CacheEntry<ViewableDocument>?, Never> _miss =
    ok<CacheEntry<ViewableDocument>?>(null);

/// The contract of `DocumentCache`, as a suite any implementation runs. On top
/// of what a meeting cache promises (owners kept apart, a miss is a value,
/// idempotent `save` and `remove`, no reference kept to what goes in or out),
/// `remove` and `purge` delete the stored content too, and an entry whose
/// content is gone is a miss.
void describeDocumentCacheContract(
  String name,
  DocumentCacheFactory createHarness,
  DocumentCacheContractOptions options,
) {
  group('$name honours the DocumentCache contract', () {
    late DocumentCacheHarness harness;
    late DocumentCache cache;

    /// A download: the content is on the device before the cache is told about
    /// it.
    Future<ViewableDocument> download(ViewableDocument viewable) async {
      await harness.files?.put(viewable.location);
      return viewable;
    }

    setUp(() async {
      harness = await createHarness();
      cache = harness.cache;
    });

    test(
      'answers a miss with a successful undefined, never an error',
      () async {
        expect(await cache.read(_owner, _viewable.document.id), equals(_miss));
      },
    );

    test('gives back a document and its location as saved, '
        'with the instant it was saved at', () async {
      await download(_viewable);

      expect(
        await cache.save(_owner, _viewable, at(10)),
        equals(ok<void>(null)),
      );

      expect(
        await cache.read(_owner, _viewable.document.id),
        equals(_entry(_viewable, 10)),
      );
    });

    test('replaces what is stored for the same owner and document', () async {
      await download(_viewable);
      final moved = _viewable.copyWith(
        location: aDocumentLocation('file:///documents/moved.pdf'),
      );
      await download(moved);

      await cache.save(_owner, _viewable, at(10));
      await cache.save(_owner, moved, at(11));

      expect(
        await cache.read(_owner, _viewable.document.id),
        equals(_entry(moved, 11)),
      );
    });

    test('tells documents apart by id', () async {
      await download(_viewable);
      await download(_otherViewable);
      await cache.save(_owner, _viewable, at(10));
      await cache.save(_owner, _otherViewable, at(11));

      expect(
        await cache.read(_owner, _otherViewable.document.id),
        equals(_entry(_otherViewable, 11)),
      );
      expect(
        await cache.read(_owner, aDocumentId('document-3')),
        equals(_miss),
      );
    });

    test('keeps the entries of two owners apart: '
        'an owner reads a miss where another saved', () async {
      await download(_viewable);
      await cache.save(_owner, _viewable, at(10));

      expect(
        await cache.read(_otherOwner, _viewable.document.id),
        equals(_miss),
      );
    });

    test('does not let one owner overwrite the entry of another', () async {
      await download(_viewable);
      await download(_otherViewable);
      await cache.save(_owner, _viewable, at(10));
      await cache.save(
        _otherOwner,
        _viewable.copyWith(document: _otherViewable.document),
        at(11),
      );
      await cache.save(_otherOwner, _viewable, at(12));

      expect(
        await cache.read(_owner, _viewable.document.id),
        equals(_entry(_viewable, 10)),
      );
    });

    test('removes one entry and leaves the others, '
        'and succeeds when the entry is absent', () async {
      await download(_viewable);
      await download(_otherViewable);
      await cache.save(_owner, _viewable, at(10));
      await cache.save(_owner, _otherViewable, at(11));

      expect(
        await cache.remove(_owner, _viewable.document.id),
        equals(ok<void>(null)),
      );
      expect(
        await cache.remove(_owner, _viewable.document.id),
        equals(ok<void>(null)),
      );
      expect(
        await cache.remove(_otherOwner, _otherViewable.document.id),
        equals(ok<void>(null)),
      );

      expect(await cache.read(_owner, _viewable.document.id), equals(_miss));
      expect(
        await cache.read(_owner, _otherViewable.document.id),
        equals(_entry(_otherViewable, 11)),
      );
    });

    test('purges every entry of every owner, '
        'and succeeds when there is none', () async {
      expect(await cache.purge(), equals(ok<void>(null)));
      await download(_viewable);
      await download(_otherViewable);
      await cache.save(_owner, _viewable, at(10));
      await cache.save(_otherOwner, _otherViewable, at(11));

      expect(await cache.purge(), equals(ok<void>(null)));

      expect(await cache.read(_owner, _viewable.document.id), equals(_miss));
      expect(
        await cache.read(_otherOwner, _otherViewable.document.id),
        equals(_miss),
      );
      expect(await cache.purge(), equals(ok<void>(null)));
    });

    group('a save that fails', () {
      test('does not leave the older entry readable '
          'as if it were current', () async {
        await download(_viewable);
        await cache.save(_owner, _viewable, at(10));
        harness.breakWrites();

        final failed = await cache.save(
          _owner,
          _viewable.copyWith(document: aDocument(title: 'Newer')),
          at(11),
        );
        harness.repairWrites();

        expect(isOk(failed), isFalse);
        expect(errorCodeOf(failed), equals(StorageErrorCode.writeFailed.value));
        expect(await cache.read(_owner, _viewable.document.id), equals(_miss));
      });

      test('leaves the entries of the other documents '
          'and owners alone', () async {
        await download(_viewable);
        await download(_otherViewable);
        await cache.save(_owner, _otherViewable, at(10));
        await cache.save(_otherOwner, _viewable, at(11));
        await cache.save(_owner, _viewable, at(12));
        harness.breakWrites();

        await cache.save(_owner, _viewable, at(13));
        harness.repairWrites();

        expect(
          await cache.read(_owner, _otherViewable.document.id),
          equals(_entry(_otherViewable, 10)),
        );
        expect(
          await cache.read(_otherOwner, _viewable.document.id),
          equals(_entry(_viewable, 11)),
        );
      });
    });

    group('the storage key is injective in the owner and the document id', () {
      test('never mixes up two pairs of (owner, document id), '
          'whatever characters they contain', () async {
        final pairs = [
          for (final owner in trickyIds)
            for (final id in trickyIds) (owner, id),
        ];
        ViewableDocument viewableOf(String owner, String id) =>
            ViewableDocument(
              document: aDocument(
                id: aDocumentId(id),
                title: jsonEncode([owner, id]),
              ),
              location: aDocumentLocation(
                'file:///documents/${_hexOf(owner)}-${_hexOf(id)}.pdf',
              ),
            );
        for (final (owner, id) in pairs) {
          final viewable = await download(viewableOf(owner, id));
          await cache.save(aUserId(owner), viewable, at(1));
        }

        for (final (owner, id) in pairs) {
          final read = await cache.read(aUserId(owner), aDocumentId(id));
          expect(
            valueOf(read)?.value.document.title,
            equals(jsonEncode([owner, id])),
          );
        }
      });
    });

    // The two checks of "keeps no reference to the objects that go in or out"
    // have no Dart scenario: a document and the entry that holds it have no
    // list to change in place, and no setter (docs/parity/exceptions.md).

    // A store without a storage to fail, or with nothing to reopen, skips
    // these: they show as skipped.
    group('a statement that fails', () {
      void failNext() {
        final fail = harness.failNextStatement;
        if (fail == null) {
          throw StateError('The harness cannot fail a statement.');
        }
        fail();
      }

      test('turns a read that fails into a storage error, '
          'and finds the entry again afterwards', () async {
        await download(_viewable);
        await cache.save(_owner, _viewable, at(10));

        failNext();
        final failed = await cache.read(_owner, _viewable.document.id);

        expect(errorCodeOf(failed), equals(StorageErrorCode.readFailed.value));
        expect(
          await cache.read(_owner, _viewable.document.id),
          equals(_entry(_viewable, 10)),
        );
      });

      test('turns a save that fails into a storage error, '
          'and leaves no older entry readable', () async {
        await download(_viewable);
        await download(_otherViewable);
        await cache.save(_owner, _viewable, at(10));
        await cache.save(_owner, _otherViewable, at(11));

        failNext();
        final failed = await cache.save(
          _owner,
          _viewable.copyWith(document: aDocument(title: 'Newer')),
          at(12),
        );

        expect(errorCodeOf(failed), equals(StorageErrorCode.writeFailed.value));
        expect(await cache.read(_owner, _viewable.document.id), equals(_miss));
        expect(
          await cache.read(_owner, _otherViewable.document.id),
          equals(_entry(_otherViewable, 11)),
        );
      });

      test('turns a removal that fails into a storage error, '
          'and keeps the entry', () async {
        await download(_viewable);
        await cache.save(_owner, _viewable, at(10));

        failNext();
        final failed = await cache.remove(_owner, _viewable.document.id);

        expect(errorCodeOf(failed), equals(StorageErrorCode.writeFailed.value));
        expect(
          await cache.read(_owner, _viewable.document.id),
          equals(_entry(_viewable, 10)),
        );
      });

      test('turns a purge that fails into a storage error, '
          'and keeps every entry, none half removed', () async {
        await download(_viewable);
        await download(_otherViewable);
        await cache.save(_owner, _viewable, at(10));
        await cache.save(_otherOwner, _otherViewable, at(11));

        failNext();
        final failed = await cache.purge();

        expect(errorCodeOf(failed), equals(StorageErrorCode.writeFailed.value));
        expect(
          await cache.read(_owner, _viewable.document.id),
          equals(_entry(_viewable, 10)),
        );
        expect(
          await cache.read(_otherOwner, _otherViewable.document.id),
          equals(_entry(_otherViewable, 11)),
        );
        expect(await cache.purge(), equals(ok<void>(null)));
      });

      test('fails once and no more: the next call works', () async {
        await download(_viewable);

        failNext();
        await cache.save(_owner, _viewable, at(10));

        expect(
          await cache.save(_owner, _viewable, at(11)),
          equals(ok<void>(null)),
        );
        expect(
          await cache.read(_owner, _viewable.document.id),
          equals(_entry(_viewable, 11)),
        );
      });
    }, skip: !options.failsStatements);

    group('closed and opened again', () {
      Future<DocumentCache> reopen() {
        final reopenStore = harness.reopen;
        if (reopenStore == null) {
          throw StateError('The harness cannot reopen the store.');
        }
        return reopenStore();
      }

      test('gives back the documents of every owner as they were, '
          'with their locations and their instants', () async {
        await download(_viewable);
        await download(_otherViewable);
        await cache.save(_owner, _viewable, at(10));
        await cache.save(_otherOwner, _otherViewable, at(11));

        final reopened = await reopen();

        expect(
          await reopened.read(_owner, _viewable.document.id),
          equals(_entry(_viewable, 10)),
        );
        expect(
          await reopened.read(_otherOwner, _otherViewable.document.id),
          equals(_entry(_otherViewable, 11)),
        );
        expect(
          await reopened.read(_otherOwner, _viewable.document.id),
          equals(_miss),
        );
      });

      test('does not give back what was removed '
          'before it was closed', () async {
        await download(_viewable);
        await download(_otherViewable);
        await cache.save(_owner, _viewable, at(10));
        await cache.save(_owner, _otherViewable, at(11));
        await cache.remove(_owner, _viewable.document.id);

        final reopened = await reopen();

        expect(
          await reopened.read(_owner, _viewable.document.id),
          equals(_miss),
        );
        expect(
          await reopened.read(_owner, _otherViewable.document.id),
          equals(_entry(_otherViewable, 11)),
        );
      });

      test('does not give back what was purged before it was closed', () async {
        await download(_viewable);
        await cache.save(_owner, _viewable, at(10));
        await cache.purge();

        final reopened = await reopen();

        expect(
          await reopened.read(_owner, _viewable.document.id),
          equals(_miss),
        );
      });
    }, skip: !options.survivesReopen);

    group('writers at the same time', () {
      test('leaves one complete version of an entry '
          'when several saves of it run together', () async {
        await download(_viewable);
        final versions = [
          for (final number in [1, 2, 3, 4, 5, 6])
            CacheEntry<ViewableDocument>(
              value: _viewable.copyWith(
                document: aDocument(title: 'Version $number'),
              ),
              cachedAt: at(number),
            ),
        ];

        await Future.wait([
          for (final version in versions)
            cache.save(_owner, version.value, version.cachedAt),
        ]);

        final read = await cache.read(_owner, _viewable.document.id);
        final held = valueOf(read);
        expect(versions, contains(held));
      });

      test('keeps every entry when saves of different documents '
          'run together', () async {
        final documents = [
          for (final number in [1, 2, 3, 4, 5])
            ViewableDocument(
              document: aDocument(
                id: aDocumentId('d-$number'),
                title: 'Document $number',
              ),
              location: aDocumentLocation('file:///documents/d-$number.pdf'),
            ),
        ];
        for (final viewable in documents) {
          await download(viewable);
        }

        await Future.wait([
          for (final (number, viewable) in documents.indexed)
            cache.save(_owner, viewable, at(number)),
        ]);

        for (final (number, viewable) in documents.indexed) {
          expect(
            await cache.read(_owner, viewable.document.id),
            equals(_entry(viewable, number)),
          );
        }
      });

      test('leaves nothing, or one complete version, '
          'when a save, a removal and reads run together', () async {
        await download(_viewable);

        final answers = await Future.wait<Result<Object?, AppError>>([
          cache.save(_owner, _viewable, at(1)),
          cache.read(_owner, _viewable.document.id),
          cache.remove(_owner, _viewable.document.id),
          cache.save(
            _owner,
            _viewable.copyWith(document: aDocument(title: 'Newer')),
            at(2),
          ),
          cache.read(_owner, _viewable.document.id),
          cache.purge(),
        ]);

        expect(answers.every(isOk), isTrue);
        final read = await cache.read(_owner, _viewable.document.id);
        final held = valueOf(read);
        expect([
          null,
          'Newer',
          _viewable.document.title,
        ], contains(held?.value.document.title));
      });
    });

    // An adapter that keeps no files (the fakes) skips these checks: they show
    // as skipped.
    group('answers for the content', () {
      /// The files of the device: the harness of an adapter that keeps them
      /// offers them.
      DocumentFiles filesOf() {
        final files = harness.files;
        if (files == null) {
          throw StateError('The harness offers no files.');
        }
        return files;
      }

      test('reads a miss when the stored content is gone, '
          'never a location that points nowhere', () async {
        await download(_viewable);
        await cache.save(_owner, _viewable, at(10));

        await filesOf().lose(_viewable.location);

        expect(await cache.read(_owner, _viewable.document.id), equals(_miss));
      });

      test('deletes the content of an entry it removes', () async {
        await download(_viewable);
        await download(_otherViewable);
        await cache.save(_owner, _viewable, at(10));
        await cache.save(_owner, _otherViewable, at(11));

        await cache.remove(_owner, _viewable.document.id);

        expect(await filesOf().exists(_viewable.location), isFalse);
        expect(await filesOf().exists(_otherViewable.location), isTrue);
      });

      test('deletes the content of every entry of every owner '
          'on purge', () async {
        await download(_viewable);
        await download(_otherViewable);
        await cache.save(_owner, _viewable, at(10));
        await cache.save(_otherOwner, _otherViewable, at(11));

        await cache.purge();

        expect(await filesOf().exists(_viewable.location), isFalse);
        expect(await filesOf().exists(_otherViewable.location), isFalse);
      });

      test('deletes the previous content when a save moves an entry '
          'to another location, so that nothing is left behind', () async {
        final moved = _viewable.copyWith(
          location: aDocumentLocation('file:///documents/moved.pdf'),
        );
        await download(_viewable);
        await cache.save(_owner, _viewable, at(10));
        await download(moved);

        await cache.save(_owner, moved, at(11));

        expect(await filesOf().exists(_viewable.location), isFalse);
        expect(await filesOf().exists(moved.location), isTrue);

        await cache.remove(_owner, _viewable.document.id);
        expect(await filesOf().exists(moved.location), isFalse);
        expect(await filesOf().exists(_viewable.location), isFalse);
      });

      test('keeps the previous content when another owner '
          'still has an entry that points at it', () async {
        final moved = _viewable.copyWith(
          location: aDocumentLocation('file:///documents/moved.pdf'),
        );
        await download(_viewable);
        await download(moved);
        await cache.save(_owner, _viewable, at(10));
        await cache.save(_otherOwner, _viewable, at(11));

        await cache.save(_owner, moved, at(12));

        expect(await filesOf().exists(_viewable.location), isTrue);
        expect(
          await cache.read(_otherOwner, _viewable.document.id),
          equals(_entry(_viewable, 11)),
        );
      });

      test('deletes the content before the entry: when the file '
          'cannot be deleted, remove fails and nothing is reported '
          'as deleted', () async {
        await download(_viewable);
        await cache.save(_owner, _viewable, at(10));
        filesOf().breakDeletion();

        final failed = await cache.remove(_owner, _viewable.document.id);

        expect(isOk(failed), isFalse);
        expect(errorCodeOf(failed), equals(StorageErrorCode.writeFailed.value));
        expect(await filesOf().exists(_viewable.location), isTrue);
        expect(
          await cache.read(_owner, _viewable.document.id),
          equals(_entry(_viewable, 10)),
        );

        filesOf().repairDeletion();
        expect(
          await cache.remove(_owner, _viewable.document.id),
          equals(ok<void>(null)),
        );
        expect(await cache.read(_owner, _viewable.document.id), equals(_miss));
        expect(await filesOf().exists(_viewable.location), isFalse);
      });

      test('purge fails too when a file cannot be deleted, '
          'keeps what it could not delete, '
          'and finishes on a second call', () async {
        await download(_viewable);
        await cache.save(_owner, _viewable, at(10));
        filesOf().breakDeletion();

        final failed = await cache.purge();

        expect(isOk(failed), isFalse);
        expect(await filesOf().exists(_viewable.location), isTrue);
        expect(
          await cache.read(_owner, _viewable.document.id),
          equals(_entry(_viewable, 10)),
        );

        filesOf().repairDeletion();
        expect(await cache.purge(), equals(ok<void>(null)));
        expect(await cache.read(_owner, _viewable.document.id), equals(_miss));
        expect(await filesOf().exists(_viewable.location), isFalse);
      });

      test('keeps a file while another owner '
          'still has an entry that points at it', () async {
        await download(_viewable);
        await cache.save(_owner, _viewable, at(10));
        await cache.save(_otherOwner, _viewable, at(11));

        await cache.remove(_owner, _viewable.document.id);

        expect(
          await cache.read(_otherOwner, _viewable.document.id),
          equals(_entry(_viewable, 11)),
        );
        expect(await filesOf().exists(_viewable.location), isTrue);

        await cache.remove(_otherOwner, _viewable.document.id);
        expect(await filesOf().exists(_viewable.location), isFalse);
      });
    }, skip: !options.keepsFiles);
  });
}
