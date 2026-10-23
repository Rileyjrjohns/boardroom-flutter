import 'dart:convert';
import 'dart:typed_data';

import 'package:boardroom/application/ports/document_cache.dart';
import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/ports/types/cache_entry.dart';
import 'package:boardroom/domain/entities/document.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/document_location.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/infrastructure/files/file_store.dart';
import 'package:boardroom/infrastructure/persistence/drift_document_cache.dart';
import 'package:boardroom/infrastructure/persistence/schema.dart';
import 'package:boardroom/infrastructure/persistence/stored_document.dart';
import 'package:test/test.dart';

import '../../application/support/contracts/document_cache_contract.dart';
import '../../application/support/fake_monitoring.dart';
import '../../domain/support/builders.dart';
import '../support/document_device.dart';
import '../support/encrypted_test_database.dart';
import '../support/faulty_file_volume.dart';
import '../support/locked_file_volume.dart';
import '../support/test_database.dart';
import '../support/test_files.dart';

/// The cache over a real SQLite database and real files, and what the suite
/// needs to wreck them.
DocumentCacheHarness _harnessOf(
  TestDatabase test,
  DocumentDevice device,
  FakeMonitoring monitoring,
) {
  final cache = DriftDocumentCache(
    DriftDocumentCacheOptions(
      database: test.database,
      files: device.store,
      monitoring: monitoring,
    ),
  );
  return DocumentCacheHarness(
    cache: cache,
    // A full disk: nothing can be added, but space can still be freed.
    breakWrites: () => test.faults.failWhileAddingData(true),
    repairWrites: () => test.faults.failWhileAddingData(false),
    failNextStatement: test.faults.failNext,
    files: device.files,
    reopen: test.file == null
        ? null
        : () async {
            final reopened = await test.reopen();
            return _harnessOf(reopened, device, monitoring).cache;
          },
  );
}

// What the contract cannot say: the format of the rows, what a row that does
// not read back becomes, the files that no row points at, and the time limits.

final UserId _owner = aUserId('owner-1');
final UserId _otherOwner = aUserId('owner-2');
final Document _document = aDocument();
final DocumentLocation _location = aDocumentLocation();
final ViewableDocument _viewable = ViewableDocument(
  document: _document,
  location: _location,
);

/// A row exactly as the first version of the cache wrote it.
final String _rowWrittenBefore = [
  '{"id":"document-1","title":"Financial statements",',
  '"confidentiality":"internal","pageCount":3}',
].join();

String get _entries => StoredTable.documentEntries.value;

void main() {
  final databases = databaseDirectory();
  final filesParent = temporaryDirectory();

  describeDocumentCacheContract(
    'DriftDocumentCache',
    () async => _harnessOf(
      await openTestDatabase(databases),
      aDocumentDevice(filesParent),
      FakeMonitoring(),
    ),
    const DocumentCacheContractOptions(
      failsStatements: true,
      survivesReopen: true,
      keepsFiles: true,
    ),
  );

  // The same suite on a database in memory, which has no file to open again.
  describeDocumentCacheContract(
    'DriftDocumentCache in memory',
    () async => _harnessOf(
      await openTestDatabase(),
      aDocumentDevice(filesParent),
      FakeMonitoring(),
    ),
    const DocumentCacheContractOptions(
      failsStatements: true,
      survivesReopen: false,
      keepsFiles: true,
    ),
  );

  // The same suite on the database the app opens: encrypted, with the key of
  // the secure storage.
  describeDocumentCacheContract(
    'DriftDocumentCache encrypted',
    () async => _harnessOf(
      await openEncryptedTestDatabase(databases),
      aDocumentDevice(filesParent),
      FakeMonitoring(),
    ),
    const DocumentCacheContractOptions(
      failsStatements: true,
      survivesReopen: true,
      keepsFiles: true,
    ),
  );

  Future<
    ({
      TestDatabase test,
      DocumentDevice device,
      LockedFileVolume locked,
      FakeMonitoring monitoring,
      DriftDocumentCache cache,
    })
  >
  openCache([int? timeoutMillis]) async {
    final test = await openTestDatabase();
    late LockedFileVolume locked;
    final device = aDocumentDevice(
      filesParent,
      timeoutMillis: timeoutMillis ?? defaultFileTimeoutMillis,
      around: (disk) => locked = LockedFileVolume(disk),
    );
    final monitoring = FakeMonitoring();
    final cache = DriftDocumentCache(
      DriftDocumentCacheOptions(
        database: test.database,
        files: device.store,
        monitoring: monitoring,
        timeoutMillis: timeoutMillis,
      ),
    );
    return (
      test: test,
      device: device,
      locked: locked,
      monitoring: monitoring,
      cache: cache,
    );
  }

  Future<Object?> rowsLeft(TestDatabase test) async =>
      (await test.database.all('SELECT count(*) AS total FROM $_entries'))
          .single['total'];

  Future<List<String>> filesLeft(DocumentDevice device) async {
    final listed = await device.store.list();
    return switch (listed) {
      Ok(:final value) => [...value]..sort(),
      Err() => <String>[],
    };
  }

  group('DriftDocumentCache, on rows written by an earlier version', () {
    test('reads a document as it was written then', () async {
      final (:test, :device, locked: _, :monitoring, :cache) =
          await openCache();
      await device.files.put(_location);
      await test.database.run(
        'INSERT INTO $_entries '
        '(owner, document_id, cached_at, location, payload) '
        'VALUES (?, ?, ?, ?, ?)',
        [_owner, _document.id, at(10), _location, _rowWrittenBefore],
      );

      expect(
        await cache.read(_owner, _document.id),
        equals(ok(CacheEntry(value: _viewable, cachedAt: at(10)))),
      );
      expect(monitoring.errors, isEmpty);
    });

    test('writes what it reads: '
        'a row written now is the row written then', () async {
      final (:test, :device, locked: _, monitoring: _, :cache) =
          await openCache();
      await device.files.put(_location);
      await cache.save(_owner, _viewable, at(10));

      final rows = await test.database.all(
        'SELECT payload, location, cached_at FROM $_entries',
      );

      expect(rows, [
        {
          'payload': _rowWrittenBefore,
          'location': _location,
          'cached_at': at(10),
        },
      ]);
      expect(
        jsonEncode(storedDocumentOf(_document).toJson()),
        equals(_rowWrittenBefore),
      );
    });

    test('keeps the location apart from the metadata, '
        'in a column of its own', () async {
      final (:test, :device, locked: _, monitoring: _, :cache) =
          await openCache();
      await device.files.put(_location);
      await cache.save(_owner, _viewable, at(10));

      final rows = await test.database.all('SELECT payload FROM $_entries');

      expect('${rows.first['payload']}', isNot(contains('file:')));
    });
  });

  group('DriftDocumentCache, on rows that no longer read back', () {
    /// Overwrites a column of the stored row behind the back of the cache.
    Future<
      ({
        TestDatabase test,
        DocumentDevice device,
        LockedFileVolume locked,
        FakeMonitoring monitoring,
        DriftDocumentCache cache,
      })
    >
    corrupt(String column, Object value) async {
      final context = await openCache();
      await context.device.files.put(_location);
      await context.cache.save(_owner, _viewable, at(10));
      await context.test.database.run('UPDATE $_entries SET $column = ?', [
        value,
      ]);
      return context;
    }

    final corruptions = <(String, String, Object)>[
      ('text that is not JSON', 'payload', 'not json at all'),
      (
        'JSON that is not the shape of a document',
        'payload',
        jsonEncode({'id': 'document-1'}),
      ),
      (
        'a document whose level nobody knows',
        'payload',
        jsonEncode({
          ...storedDocumentOf(_document).toJson(),
          'confidentiality': 'secret',
        }),
      ),
      (
        'a document with a blank title',
        'payload',
        jsonEncode({...storedDocumentOf(_document).toJson(), 'title': '  '}),
      ),
      ('an instant that is not one', 'cached_at', -1),
      ('a location that is blank', 'location', '   '),
      (
        'a location that is no file of the store',
        'location',
        'memory://documents/1/user/doc',
      ),
    ];
    for (final (name, column, value) in corruptions) {
      test('reads $name as a miss, reports it, and deletes the row', () async {
        final (:test, locked: _, device: _, :monitoring, :cache) =
            await corrupt(column, value);

        expect(
          await cache.read(_owner, _document.id),
          equals(ok<CacheEntry<Object?>?>(null)),
        );

        expect(
          monitoring.capturedEvents(),
          equals([MonitoringEvent.storedRowDiscarded]),
        );
        expect(await rowsLeft(test), equals(0));
      });
    }

    test('deletes the file of a row it cannot read, '
        'and not the file another owner needs', () async {
      final (:test, :device, locked: _, monitoring: _, :cache) = await corrupt(
        'payload',
        'not json at all',
      );
      await device.files.put(aDocumentLocation('file:///documents/kept.pdf'));
      await test.database.run(
        'INSERT INTO $_entries '
        '(owner, document_id, cached_at, location, payload) '
        'VALUES (?, ?, ?, ?, ?)',
        [_otherOwner, _document.id, at(11), _location, _rowWrittenBefore],
      );

      await cache.read(_owner, _document.id);

      // The other owner still points at it.
      expect(await filesLeft(device), equals(['document-1.pdf', 'kept.pdf']));
      expect(
        await cache.read(_otherOwner, _document.id),
        equals(ok(CacheEntry(value: _viewable, cachedAt: at(11)))),
      );
    });

    test('deletes the file of a row it cannot read '
        'when nobody else needs it', () async {
      final (test: _, :device, locked: _, monitoring: _, :cache) =
          await corrupt('payload', 'not json at all');

      await cache.read(_owner, _document.id);

      expect(await filesLeft(device), isEmpty);
    });

    test('puts no path, location, title nor value '
        'in what it reports', () async {
      final (
        test: _,
        device: _,
        locked: _,
        :monitoring,
        :cache,
      ) = await corrupt(
        'payload',
        jsonEncode({
          ...storedDocumentOf(_document).toJson(),
          'title': '   ',
          'secret': 'Remuneration',
        }),
      );

      await cache.read(_owner, _document.id);

      expect(
        '${monitoring.errors}',
        isNot(matches(RegExp('documents|Financial|Remuneration|owner-1'))),
      );
    });

    test('drops the row of a document whose content is gone, '
        'and only while it still points there', () async {
      final (:test, :device, locked: _, monitoring: _, :cache) =
          await openCache();
      await device.files.put(_location);
      await cache.save(_owner, _viewable, at(10));
      await device.files.lose(_location);

      expect(
        await cache.read(_owner, _document.id),
        equals(ok<CacheEntry<Object?>?>(null)),
      );

      expect(await rowsLeft(test), equals(0));
    });

    test(
      'fails the read, and keeps the row, '
      'when the file system cannot say whether the content is there',
      () async {
        final (:test, :device, locked: _, monitoring: _, :cache) =
            await openCache();
        await device.files.put(_location);
        await cache.save(_owner, _viewable, at(10));
        device.volume.fail(VolumeCall.size, true);

        final failed = await cache.read(_owner, _document.id);

        expect(failed, equals(err(storageReadFailed('os error 5'))));
        expect(await rowsLeft(test), equals(1));
      },
    );
  });

  group('DriftDocumentCache, the content', () {
    test('shares a file between owners by count: '
        'it goes with the last entry that points at it', () async {
      final (test: _, :device, locked: _, monitoring: _, :cache) =
          await openCache();
      await device.files.put(_location);
      await cache.save(_owner, _viewable, at(10));
      await cache.save(_otherOwner, _viewable, at(11));
      await cache.save(
        _owner,
        ViewableDocument(
          document: aConfidentialDocument(),
          location: _location,
        ),
        at(12),
      );

      await cache.remove(_owner, _document.id);
      expect(await filesLeft(device), equals(['document-1.pdf']));

      await cache.remove(_otherOwner, _document.id);
      expect(await filesLeft(device), isEmpty);
    });

    test('drops the entry of a save that moves it, '
        'even when the file it leaves cannot be deleted', () async {
      final (:test, :device, locked: _, monitoring: _, :cache) =
          await openCache();
      final moved = ViewableDocument(
        document: _document,
        location: aDocumentLocation('file:///documents/moved.pdf'),
      );
      await device.files.put(_location);
      await device.files.put(moved.location);
      await cache.save(_owner, _viewable, at(10));
      device.files.breakDeletion();

      final failed = await cache.save(_owner, moved, at(11));

      expect(
        failed,
        isA<Err<void, StorageWriteFailedError>>().having(
          (result) => result.error.code,
          'code',
          StorageErrorCode.writeFailed.value,
        ),
      );
      // The older entry is not served as if it were current, and the file it
      // left is for the sweep.
      expect(await rowsLeft(test), equals(0));
      device.files.repairDeletion();
      expect(await cache.sweepOrphans(), equals(ok<void>(null)));
      expect(await filesLeft(device), isEmpty);
    });

    test('purges the files no entry points at as well', () async {
      final (test: _, :device, locked: _, monitoring: _, :cache) =
          await openCache();
      await device.files.put(_location);
      await device.files.put(aDocumentLocation('file:///documents/orphan.pdf'));
      await cache.save(_owner, _viewable, at(10));

      expect(await cache.purge(), equals(ok<void>(null)));

      expect(await filesLeft(device), isEmpty);
    });

    test('removes the entries whose file was deleted on a purge, '
        'and keeps the ones whose file was not', () async {
      final (:test, :device, :locked, monitoring: _, :cache) =
          await openCache();
      final other = ViewableDocument(
        document: aConfidentialDocument(),
        location: aDocumentLocation('file:///documents/other.pdf'),
      );
      await device.files.put(_location);
      await device.files.put(other.location);
      await cache.save(_owner, _viewable, at(10));
      await cache.save(_owner, other, at(11));
      // Only the file of the second document cannot be deleted.
      locked.lock('other.pdf');

      final failed = await cache.purge();

      expect(
        failed,
        equals(err(storageWriteFailed('os error $busyErrorNumber'))),
      );
      final rows = await test.database.all('SELECT document_id FROM $_entries');
      expect([for (final row in rows) row['document_id']], [other.document.id]);
      expect(await filesLeft(device), equals(['other.pdf']));
    });
  });

  group('DriftDocumentCache, a row whose location is no location', () {
    test('is removed by a purge, with the rest', () async {
      final (:test, :device, locked: _, monitoring: _, :cache) =
          await openCache();
      await device.files.put(_location);
      await cache.save(_owner, _viewable, at(10));
      await test.database.run(
        'INSERT INTO $_entries '
        '(owner, document_id, cached_at, location, payload) '
        'VALUES (?, ?, ?, ?, ?)',
        [_otherOwner, 'document-2', at(11), '   ', _rowWrittenBefore],
      );

      expect(await cache.purge(), equals(ok<void>(null)));

      expect(await rowsLeft(test), equals(0));
      expect(await filesLeft(device), isEmpty);
    });

    test('is not a file the sweep keeps', () async {
      final (:test, :device, locked: _, monitoring: _, :cache) =
          await openCache();
      await device.files.put(aDocumentLocation('file:///documents/orphan.pdf'));
      await test.database.run(
        'INSERT INTO $_entries '
        '(owner, document_id, cached_at, location, payload) '
        'VALUES (?, ?, ?, ?, ?)',
        [_otherOwner, 'document-2', at(11), '   ', _rowWrittenBefore],
      );

      expect(await cache.sweepOrphans(), equals(ok<void>(null)));

      expect(await filesLeft(device), isEmpty);
      expect(await rowsLeft(test), equals(1));
    });
  });

  group('DriftDocumentCache, the files that no entry points at', () {
    test('deletes them when it starts, '
        'and keeps the ones an entry points at', () async {
      final (test: _, :device, locked: _, monitoring: _, :cache) =
          await openCache();
      await device.files.put(_location);
      await cache.save(_owner, _viewable, at(10));
      await device.files.put(aDocumentLocation('file:///documents/orphan.pdf'));
      await device.volume.write(
        'document-9.pdf.abc1.part',
        Uint8List.fromList([1]),
      );

      expect(await cache.sweepOrphans(), equals(ok<void>(null)));

      expect(await filesLeft(device), equals(['document-1.pdf']));
      expect(
        await cache.read(_owner, _document.id),
        equals(ok(CacheEntry(value: _viewable, cachedAt: at(10)))),
      );
    });

    test('keeps a file that a row of another owner points at', () async {
      final (test: _, :device, locked: _, monitoring: _, :cache) =
          await openCache();
      await device.files.put(_location);
      await cache.save(_otherOwner, _viewable, at(10));

      await cache.sweepOrphans();

      expect(await filesLeft(device), equals(['document-1.pdf']));
    });

    test('does nothing when the directory does not exist yet', () async {
      final (test: _, device: _, locked: _, monitoring: _, :cache) =
          await openCache();

      expect(await cache.sweepOrphans(), equals(ok<void>(null)));
    });

    test('goes on with the other files when one cannot be deleted, '
        'and fails without reporting it', () async {
      final (test: _, :device, :locked, :monitoring, :cache) =
          await openCache();
      await device.files.put(aDocumentLocation('file:///documents/a.pdf'));
      await device.files.put(aDocumentLocation('file:///documents/b.pdf'));
      locked.lock('a.pdf');

      final failed = await cache.sweepOrphans();

      expect(
        failed,
        isA<Err<void, StorageWriteFailedError>>().having(
          (result) => result.error.code,
          'code',
          StorageErrorCode.writeFailed.value,
        ),
      );
      // The composition root reports the failure of the sweep, once: the cache
      // does not.
      expect(monitoring.capturedEvents(), isEmpty);
      expect(await filesLeft(device), equals(['a.pdf']));
    });

    test('fails when the files cannot be listed', () async {
      final (test: _, :device, locked: _, monitoring: _, :cache) =
          await openCache();
      device.volume.fail(VolumeCall.list, true);

      final failed = await cache.sweepOrphans();

      expect(failed, equals(err(storageWriteFailed('os error 5'))));
    });
  });

  group('DriftDocumentCache, in bounded time', () {
    const short = 30;

    test('fails a read when the file system never answers', () async {
      final (test: _, :device, locked: _, monitoring: _, :cache) =
          await openCache(short);
      await device.files.put(_location);
      await cache.save(_owner, _viewable, at(10));
      device.volume.hang(VolumeCall.size, true);

      final failed = await cache.read(_owner, _document.id);

      expect(failed, equals(err(storageReadFailed('timeout'))));
    });

    test('fails a removal when the database never answers', () async {
      final (:test, device: _, locked: _, monitoring: _, :cache) =
          await openCache(short);
      test.faults.hang(true);

      final failed = await cache.remove(_owner, _document.id);

      expect(failed, equals(err(storageWriteFailed('timeout'))));
    });
  });
}
