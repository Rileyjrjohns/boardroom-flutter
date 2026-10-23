import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:boardroom/app/persistence/boardroom_database.dart';
import 'package:boardroom/app/persistence/migrations.dart' as schema;
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/persistence/database_key.dart';
import 'package:boardroom/core/infrastructure/persistence/database_opener.dart'
    show connectionPragmas;
import 'package:boardroom/core/infrastructure/persistence/local_data_reset.dart';
import 'package:boardroom/core/infrastructure/persistence/migrate.dart';
import 'package:boardroom/core/infrastructure/persistence/protected_database.dart';
import 'package:boardroom/core/infrastructure/persistence/random_key.dart';
import 'package:boardroom/core/infrastructure/persistence/sqlite3_opener.dart';
import 'package:boardroom/core/infrastructure/persistence/unlock_database.dart';
import 'package:boardroom/core/infrastructure/secure_storage/secure_storage.dart';
import 'package:boardroom/features/meetings/infrastructure/persistence/schema.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:test/test.dart';

import '../../../support/fakes/fake_monitoring.dart';
import '../../../support/infrastructure/memory_secure_storage.dart';
import '../../../support/infrastructure/test_database.dart';
import '../../../support/infrastructure/test_files.dart';
import '../../../support/infrastructure/watched_opener.dart';

/// What the keychain holds for the database: the generation of the file, and
/// the key.
final RegExp _stateFormat = RegExp(r'^[0-9]+:[0-9a-f]{64}$');
final String _otherKey = 'c' * 64;

/// A keychain the tests can make refuse a write, and that notes the keys
/// written, in order, in the log it is given.
final class _Keychain implements SecureStorage {
  new(this.inner, this.log);

  final MemorySecureStorage inner;
  final List<String> log;
  final Set<String> _refusedKeys = {};
  int _refusedWrites = 0;

  /// The next [count] writes are refused, whatever their key.
  // ignore: use_setters_to_change_properties, a switch of the test.
  void refuseNextWrites([int count = 1]) {
    _refusedWrites = count;
  }

  /// Every write of this key is refused.
  void refuseKey(String key) {
    _refusedKeys.add(key);
  }

  Map<String, String> snapshot() => inner.snapshot();

  void seed(String key, String value) => inner.seed(key, value);

  void failNext() => inner.failNext();

  void hang() => inner.hang();

  @override
  Future<String?> get(String key) => inner.get(key);

  @override
  Future<void> set(String key, String value) {
    log.add(key);
    if (_refusedWrites > 0) {
      _refusedWrites -= 1;
      return Future.error(StateError('full'));
    }
    if (_refusedKeys.contains(key)) {
      return Future.error(StateError('full'));
    }
    return inner.set(key, value);
  }

  @override
  Future<void> remove(String key) => inner.remove(key);
}

/// A device: a keychain, a file system and the logs, that survive the app being
/// started again.
final class _Device {
  new(Directory parent, {RandomBytes? randomBytes})
    : _randomBytes = randomBytes ?? secureRandomBytes,
      _directory = Directory('${freshDirectory(parent).path}/databases'),
      name = 'protected-${_counter++}.db';

  static int _counter = 0;

  final RandomBytes _randomBytes;
  final Directory _directory;

  /// The name of the first file of the database.
  final String name;

  /// The opens and the writes to the keychain, in order.
  final List<String> log = [];

  late final _Keychain storage = _Keychain(MemorySecureStorage(), log);
  final FakeMonitoring monitoring = FakeMonitoring();
  late final WatchedOpener opener = WatchedOpener(
    Sqlite3Opener(_directory),
    _directory,
    log,
  );

  /// A start of the app.
  Future<Result<BoardroomDatabase, DatabaseUnavailable>> start({
    List<Migration>? migrations,
    int? timeoutMillis,
  }) => openProtectedDatabase(
    ProtectedDatabaseOptions(
      opener: opener,
      storage: storage,
      randomBytes: _randomBytes,
      monitoring: monitoring,
      name: name,
      migrations: migrations ?? schema.migrations,
      databaseFactory: createBoardroomDatabase,
      timeoutMillis: timeoutMillis,
    ),
  );

  String? get key => storage.snapshot()[SecureStorageKey.databaseKey.value];
}

Future<BoardroomDatabase> _started(_Device device) async {
  final opened = await device.start();
  switch (opened) {
    case Ok(:final value):
      addTearDown(value.close);
      return value;
    case Err(:final error):
      throw StateError('The database should have opened: $error');
  }
}

Future<void> _mark(BoardroomDatabase database) => database.run(
  'INSERT INTO ${MeetingStoredTable.meetingDetails.value} '
  "(owner, meeting_id, cached_at, payload) VALUES ('o', 'm', 1, '{}')",
);

Future<Object?> _rowsOf(
  BoardroomDatabase database,
) async => (await database.all(
  'SELECT count(*) AS total FROM ${MeetingStoredTable.meetingDetails.value}',
)).single['total'];

Err<Never, DatabaseUnavailable> _unavailable(DatabaseFailureReason reason) =>
    err(DatabaseUnavailable(reason));

/// The last 64 characters of what the keychain holds: the key, without the
/// generation.
String _bareKey(String? state) => state!.substring(state.length - 64);

void main() {
  final parent = temporaryDirectory();
  // Many databases are opened one after the other, and left to the end of the
  // test: drift's warning is for a program that uses two of them at once.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('openProtectedDatabase', () {
    group('the first start', () {
      test('makes a 256-bit key, keeps it in the secure storage, '
          'and creates the database with it', () async {
        final device = _Device(parent);

        final database = await _started(device);

        final key = device.key;
        expect(key, matches(_stateFormat));
        expect(device.opener.keysUsed, equals([_bareKey(key)]));
        expect(
          await database.all('PRAGMA user_version'),
          equals([
            {'user_version': schema.migrations.length},
          ]),
        );
        expect(device.monitoring.logs, isEmpty);
      });

      test('sets the connection up to overwrite what is deleted, '
          'so that a removed vote does not stay in the file', () async {
        final device = _Device(parent);

        final database = await _started(device);

        expect(
          await database.all('PRAGMA secure_delete'),
          equals([
            {'secure_delete': 1},
          ]),
        );
      });

      test('makes a different key for each installation', () async {
        final keys = <String?>{};
        for (var installation = 0; installation < 5; installation++) {
          final device = _Device(parent);
          await _started(device);
          keys.add(device.key);
        }

        expect(keys, hasLength(5));
      });

      test('stores the key before the database exists, '
          'so that a start stopped in between loses nothing', () async {
        final device = _Device(parent);
        device.opener.failNextOpens();

        final stopped = await device.start();

        expect(stopped, equals(_unavailable(DatabaseFailureReason.open)));
        final keptKey = device.key;
        expect(keptKey, matches(_stateFormat));
        expect(device.opener.has(device.name), isFalse);

        final database = await _started(device);
        expect(
          await database.all('PRAGMA user_version'),
          equals([
            {'user_version': schema.migrations.length},
          ]),
        );
        expect(device.key, equals(keptKey));
        expect(device.opener.keysUsed, equals([_bareKey(keptKey)]));
      });
    });

    group('the starts after', () {
      test('opens the database with the key it kept, '
          'and finds what was in it', () async {
        final device = _Device(parent);
        final first = await _started(device);
        await _mark(first);
        await first.close();
        final key = device.key;

        final second = await _started(device);

        expect(await _rowsOf(second), equals(1));
        expect(device.key, equals(key));
        expect(device.opener.keysUsed, equals([_bareKey(key), _bareKey(key)]));
        expect(device.monitoring.logs, isEmpty);
      });

      test('migrates a database from an older version of the app', () async {
        final device = _Device(parent);
        final first = await device.start(
          migrations: schema.migrations.sublist(0, 1),
        );
        await _mark(
          (first as Ok<BoardroomDatabase, DatabaseUnavailable>).value,
        );
        await first.value.close();

        final second = await _started(device);

        expect(
          await second.all('PRAGMA user_version'),
          equals([
            {'user_version': schema.migrations.length},
          ]),
        );
        expect(await _rowsOf(second), equals(1));
      });
    });

    group('a key that is lost, rejected or a file that is not a database', () {
      final losses =
          <
            (
              String,
              ResetReason,
              Future<void> Function(_Device),
              bool, // whether the old file can still be read with its own key
            )
          >[
            (
              'the key is not in the keychain',
              ResetReason.keyLost,
              (device) async {
                await device.storage.inner.remove(
                  SecureStorageKey.databaseKey.value,
                );
              },
              true,
            ),
            (
              'the keychain holds another key',
              ResetReason.keyRejected,
              (device) async {
                await device.storage.inner.set(
                  SecureStorageKey.databaseKey.value,
                  formatKeyState(KeyState(generation: 0, key: _otherKey)),
                );
              },
              true,
            ),
            (
              'the file is not a database',
              ResetReason.keyRejected,
              (device) async {
                device.opener.corrupt(device.name);
              },
              false,
            ),
          ];
      for (final (name, reason, lose, readable) in losses) {
        group('when $name', () {
          test('sets the file aside, unread and not deleted, '
              'and starts a new database, empty, in another file', () async {
            final device = _Device(parent);
            final first = await _started(device);
            await _mark(first);
            await first.close();
            final originalKey = device.key;
            await lose(device);

            final second = await _started(device);

            expect(await _rowsOf(second), equals(0));
            expect(device.opener.exists(device.name), isTrue);
            expect(
              device.opener.exists(databaseFileName(device.name, 1)),
              isTrue,
            );
            expect(device.opener.removed, isEmpty);
            expect(device.key, matches(_stateFormat));
            expect(device.key, contains('1:'));
            expect(device.key, isNot(contains(_bareKey(originalKey))));
          });

          test('leaves the data of the old file where it was, '
              'readable with its own key when it can be read', () async {
            final device = _Device(parent);
            final first = await _started(device);
            await _mark(first);
            await first.close();
            final originalKey = _bareKey(device.key);
            await lose(device);

            await _started(device);

            // A file that is not a database is readable by nobody: only that
            // it was kept can be seen.
            expect(device.opener.exists(device.name), isTrue);
            final old = await device.opener.open(device.name);
            final unlocked = await unlockDatabase(old, originalKey);
            expect(unlocked is Ok, equals(readable));
            if (readable) {
              expect(
                await old.all(
                  'SELECT count(*) AS total '
                  'FROM ${MeetingStoredTable.meetingDetails.value}',
                ),
                equals([
                  {'total': 1},
                ]),
              );
            }
            await old.close();
          });

          test('reports it as an error to the monitoring, with the reason, '
              'and not as a log', () async {
            final device = _Device(parent);
            final first = await _started(device);
            await first.close();
            await lose(device);

            await _started(device);

            expect(
              device.monitoring.errors,
              equals([
                ErrorRecord(
                  event: MonitoringEvent.databaseRecreated,
                  error: storageReadFailed(reason.value),
                  attributes: {LogAttribute.reason: reason.value},
                ),
              ]),
            );
            expect(device.monitoring.logs, isEmpty);
          });

          test('leaves a record in the keychain that local data was reset, '
              'with the reason', () async {
            final device = _Device(parent);
            final first = await _started(device);
            await first.close();
            await lose(device);

            await _started(device);

            expect(
              device.storage.snapshot()[SecureStorageKey.localDataReset.value],
              equals(reason.value),
            );
          });

          test('uses the new file at the starts after, '
              'and the record stays until somebody clears it', () async {
            final device = _Device(parent);
            final first = await _started(device);
            await first.close();
            await lose(device);
            final second = await _started(device);
            await _mark(second);
            await second.close();

            final third = await _started(device);

            expect(await _rowsOf(third), equals(1));
            expect(device.monitoring.errors, hasLength(1));
            expect(
              device.storage.snapshot()[SecureStorageKey.localDataReset.value],
              equals(reason.value),
            );
          });
        });
      }

      test('keeps the key that did not open the file '
          'when the keychain had one, and none when it had not', () async {
        final rejected = _Device(parent);
        await (await _started(rejected)).close();
        final originalKey = rejected.key ?? '';
        await rejected.storage.inner.set(
          SecureStorageKey.databaseKey.value,
          formatKeyState(KeyState(generation: 0, key: _otherKey)),
        );
        await _started(rejected);

        final lost = _Device(parent);
        await (await _started(lost)).close();
        await lost.storage.inner.remove(SecureStorageKey.databaseKey.value);
        await _started(lost);

        expect(
          rejected.storage
              .snapshot()[SecureStorageKey.databaseKeyPrevious.value],
          equals(formatKeyState(KeyState(generation: 0, key: _otherKey))),
        );
        expect(originalKey, matches(_stateFormat));
        expect(
          lost.storage.snapshot()[SecureStorageKey.databaseKeyPrevious.value],
          isNull,
        );
      });

      test('keeps at most one copy: '
          'the second reset removes the copy of the first', () async {
        final device = _Device(parent);
        await (await _started(device)).close();
        await device.storage.inner.set(
          SecureStorageKey.databaseKey.value,
          formatKeyState(KeyState(generation: 0, key: _otherKey)),
        );
        await (await _started(device)).close();
        // The file of generation 1 is lost in its turn.
        device.storage.seed(
          SecureStorageKey.databaseKey.value,
          formatKeyState(KeyState(generation: 1, key: _otherKey)),
        );

        final third = await _started(device);

        expect(await _rowsOf(third), equals(0));
        expect(device.opener.exists(databaseFileName(device.name, 2)), isTrue);
        expect(device.opener.exists(databaseFileName(device.name, 1)), isTrue);
        expect(device.opener.exists(databaseFileName(device.name, 0)), isFalse);
        expect(
          device.opener.removed,
          equals([databaseFileName(device.name, 0)]),
        );
      });

      test('resets at most once in a start: '
          'a new file that is no good either is a failure to open', () async {
        final device = _Device(parent);
        await (await _started(device)).close();
        await device.storage.inner.remove(SecureStorageKey.databaseKey.value);
        device.opener.corrupt(databaseFileName(device.name, 1));

        final failed = await device.start();

        expect(failed, equals(_unavailable(DatabaseFailureReason.open)));
        expect(device.opener.exists(device.name), isTrue);
      });

      test('is told before anything is set aside: '
          'a record, then the key, then the file', () async {
        final device = _Device(parent);
        await (await _started(device)).close();
        await device.storage.inner.set(
          SecureStorageKey.databaseKey.value,
          formatKeyState(KeyState(generation: 0, key: _otherKey)),
        );
        device.log.clear();

        await _started(device);

        expect(
          device.log,
          equals([
            'open ${device.name}',
            SecureStorageKey.localDataReset.value,
            SecureStorageKey.databaseKeyPrevious.value,
            SecureStorageKey.databaseKey.value,
            'open ${databaseFileName(device.name, 1)}',
          ]),
        );
      });

      test('does not set anything aside when the record cannot be written, '
          'and the key is untouched', () async {
        final device = _Device(parent);
        await (await _started(device)).close();
        await device.storage.inner.set(
          SecureStorageKey.databaseKey.value,
          formatKeyState(KeyState(generation: 0, key: _otherKey)),
        );
        final before = device.key;
        device.storage.refuseKey(SecureStorageKey.localDataReset.value);

        final failed = await device.start();

        expect(failed, equals(_unavailable(DatabaseFailureReason.keyStorage)));
        expect(device.key, equals(before));
        expect(device.opener.exists(databaseFileName(device.name, 1)), isFalse);
        expect(device.monitoring.errors, isEmpty);
      });

      test('does not start over when the new key cannot be kept: '
          'the file is not set aside', () async {
        final device = _Device(parent);
        await (await _started(device)).close();
        await device.storage.inner.set(
          SecureStorageKey.databaseKey.value,
          formatKeyState(KeyState(generation: 0, key: _otherKey)),
        );
        final before = device.key;
        device.storage.refuseKey(SecureStorageKey.databaseKey.value);

        final failed = await device.start();

        expect(failed, equals(_unavailable(DatabaseFailureReason.keyStorage)));
        expect(device.key, equals(before));
        expect(device.monitoring.errors, isEmpty);
        expect(device.opener.removed, isEmpty);
      });

      test('goes on when the previous key cannot be kept: '
          'it is only a help', () async {
        final device = _Device(parent);
        await (await _started(device)).close();
        await device.storage.inner.set(
          SecureStorageKey.databaseKey.value,
          formatKeyState(KeyState(generation: 0, key: _otherKey)),
        );
        device.storage.refuseKey(SecureStorageKey.databaseKeyPrevious.value);

        final second = await _started(device);

        expect(await _rowsOf(second), equals(0));
      });

      test('finishes the reset at the next start '
          'when the app stopped after the key was renewed', () async {
        final device = _Device(parent);
        final first = await _started(device);
        await _mark(first);
        await first.close();
        await device.storage.inner.set(
          SecureStorageKey.databaseKey.value,
          formatKeyState(KeyState(generation: 0, key: _otherKey)),
        );
        // The start stops when the new file is opened for the first time.
        device.opener.failOpenNumber(device.opener.opens + 2);
        final stopped = await device.start();

        final restarted = await _started(device);

        expect(stopped is Err, isTrue);
        expect(await _rowsOf(restarted), equals(0));
        expect(device.monitoring.errors, hasLength(1));
        expect(device.opener.exists(device.name), isTrue);
        expect(
          device.storage.snapshot()[SecureStorageKey.localDataReset.value],
          equals(ResetReason.keyRejected.value),
        );
      });
    });

    group('a keychain that cannot be trusted', () {
      final notKeys = <(String, String)>[
        ('text that is not a key', 'not a key'),
        ('a key of the wrong length', 'a' * 63),
        ('a key in upper case', 'A' * 64),
        ('an empty value', ''),
        ('a generation with no key', '1:'),
        ('a generation that is not a number', 'x:${'a' * 64}'),
      ];
      for (final (name, value) in notKeys) {
        test('fails closed for $name: '
            'nothing is made, set aside or deleted', () async {
          final device = _Device(parent);
          final first = await _started(device);
          await _mark(first);
          await first.close();
          device.storage.seed(SecureStorageKey.databaseKey.value, value);

          final failed = await device.start();

          expect(
            failed,
            equals(_unavailable(DatabaseFailureReason.keyStorage)),
          );
          expect(device.key, equals(value));
          expect(
            device.storage.snapshot()[SecureStorageKey.localDataReset.value],
            isNull,
          );
          expect(device.opener.removed, isEmpty);
          expect(device.monitoring.errors, isEmpty);
          expect(device.opener.exists(device.name), isTrue);
        });
      }

      test('reads the key an app that knew one file kept, '
          'as the key of the first file', () async {
        final device = _Device(parent);
        final first = await _started(device);
        await _mark(first);
        await first.close();
        final key = _bareKey(device.key);
        device.storage.seed(SecureStorageKey.databaseKey.value, key);

        final second = await _started(device);

        expect(await _rowsOf(second), equals(1));
        expect(device.monitoring.errors, isEmpty);
      });
    });

    group('two starts at once on the same keychain', () {
      test('make one key, and the database both open is the one '
          'with the data', () async {
        final device = _Device(parent);

        final (one, other) = await (device.start(), device.start()).wait;

        expect(one is Ok && other is Ok, isTrue);
        if (one is! Ok<BoardroomDatabase, DatabaseUnavailable> ||
            other is! Ok<BoardroomDatabase, DatabaseUnavailable>) {
          return;
        }
        await _mark(one.value);
        expect(await _rowsOf(other.value), equals(1));
        expect(device.opener.keysUsed.toSet(), hasLength(1));
        expect(device.monitoring.errors, isEmpty);
        expect(
          device.storage.snapshot()[SecureStorageKey.localDataReset.value],
          isNull,
        );
      });

      test('do not hold each other up '
          'when the keychains are not the same', () async {
        final first = _Device(parent);
        final second = _Device(parent);
        first.storage.hang();

        final (stuck, free) = await (
          first.start(timeoutMillis: 20),
          second.start(),
        ).wait;

        expect(stuck is Err, isTrue);
        expect(free is Ok, isTrue);
      });

      test('go on one after the other when the first fails', () async {
        final device = _Device(parent);
        device.storage.failNext();

        final (failed, retried) = await (device.start(), device.start()).wait;

        expect(failed is Err, isTrue);
        expect(retried is Ok, isTrue);
      });
    });

    group('when the keychain does not work', () {
      test('does not start, and touches nothing, '
          'when the key cannot be read', () async {
        final device = _Device(parent);
        device.storage.failNext();

        final opened = await device.start();

        expect(opened, equals(_unavailable(DatabaseFailureReason.keyStorage)));
        expect(device.opener.keysUsed, isEmpty);
      });

      test('does not create the database '
          'when the key it made cannot be kept', () async {
        final device = _Device(parent);
        device.storage.refuseNextWrites();

        final opened = await device.start();

        expect(opened, equals(_unavailable(DatabaseFailureReason.keyStorage)));
        expect(device.opener.has(device.name), isFalse);
        expect(device.opener.exists(device.name), isFalse);
      });

      test(
        'does not wait for ever for a keychain that does not answer',
        () async {
          final device = _Device(parent);
          device.storage.hang();

          final opened = await device.start(timeoutMillis: 20);

          expect(
            opened,
            equals(_unavailable(DatabaseFailureReason.keyStorage)),
          );
        },
      );
    });

    group('where the key comes from', () {
      test('draws 32 bytes from the random source it is given, '
          'and keeps them as 64 lower-case hexadecimal digits', () async {
        final asked = <int>[];
        final bytes = Uint8List.fromList([
          for (var index = 0; index < 32; index++) 0xa0 + index,
        ]);
        final device = _Device(
          parent,
          randomBytes: (count) async {
            asked.add(count);
            return bytes;
          },
        );

        await _started(device);

        expect(asked, equals([32]));
        expect(
          device.key,
          equals(
            '0:${'a0a1a2a3a4a5a6a7a8a9aaabacadaeaf'}'
            '${'b0b1b2b3b4b5b6b7b8b9babbbcbdbebf'}',
          ),
        );
      });

      test('draws again for the key of the next file '
          'when the database is reset', () async {
        final asked = <int>[];
        final device = _Device(
          parent,
          randomBytes: (count) {
            asked.add(count);
            return secureRandomBytes(count);
          },
        );
        final first = await _started(device);
        await first.close();
        device.opener.corrupt(device.name);

        await _started(device);

        expect(asked, equals([32, 32]));
      });

      test('opens a database made by an earlier version, '
          'whose key was made by SQLite in the same form', () async {
        final device = _Device(parent);
        final database = await _started(device);
        await _mark(database);
        await database.close();
        final kept = device.key;

        final again = await _started(device);

        expect(await _rowsOf(again), equals(1));
        expect(device.key, equals(kept));
      });
    });

    group('when no random key can be made', () {
      final failed = _unavailable(DatabaseFailureReason.keyStorage);

      final generators = <(String, Future<Uint8List> Function(int))>[
        ('the generator rejects', (_) => Future.error(Exception('no entropy'))),
        ('the generator throws', (_) => throw Exception('no entropy')),
        (
          'it answers too few bytes',
          (_) async => Uint8List(16)..fillRange(0, 16, 7),
        ),
        (
          'it answers too many bytes',
          (_) async => Uint8List(33)..fillRange(0, 33, 7),
        ),
        ('it answers nothing', (_) async => Uint8List(0)),
        ('it answers zeros', (_) async => Uint8List(32)),
      ];
      for (final (name, generator) in generators) {
        test('does not start, and stores and creates nothing, '
            'when $name', () async {
          final device = _Device(parent, randomBytes: generator);

          final opened = await device.start();

          expect(opened, equals(failed));
          expect(device.storage.snapshot(), isEmpty);
          expect(device.opener.has(device.name), isFalse);
        });
      }

      test(
        'does not wait for ever for a generator that does not answer',
        () async {
          final device = _Device(
            parent,
            randomBytes: (_) => Completer<Uint8List>().future,
          );

          final opened = await device.start(timeoutMillis: 20);

          expect(opened, equals(failed));
          expect(device.storage.snapshot(), isEmpty);
        },
      );

      test('starts when the generator works again', () async {
        var failing = true;
        final device = _Device(
          parent,
          randomBytes: (count) => failing
              ? Future.error(Exception('no entropy'))
              : secureRandomBytes(count),
        );
        expect(await device.start(), equals(failed));

        failing = false;

        expect((await device.start()) is Ok, isTrue);
      });
    });

    group('when the database cannot be had', () {
      test('refuses to store anything in clear when the engine cannot encrypt, '
          'and says why', () async {
        final device = _Device(parent);
        device.opener.setCipher(available: false);

        final opened = await device.start();

        expect(
          opened,
          equals(_unavailable(DatabaseFailureReason.encryptionUnavailable)),
        );
        expect(device.opener.has(device.name), isFalse);
      });

      test('does not delete a database it merely failed to open', () async {
        final device = _Device(parent);
        final first = await _started(device);
        await _mark(first);
        await first.close();
        device.opener.failNextOpens();

        final failed = await device.start();
        final again = await _started(device);

        expect(failed, equals(_unavailable(DatabaseFailureReason.open)));
        expect(await _rowsOf(again), equals(1));
        expect(device.monitoring.errors, isEmpty);
        expect(device.opener.removed, isEmpty);
      });

      test('goes on when the copy of an earlier reset cannot be removed: '
          'it is only disk space', () async {
        final device = _Device(parent);
        await (await _started(device)).close();
        device.storage.seed(
          SecureStorageKey.databaseKey.value,
          formatKeyState(KeyState(generation: 1, key: _otherKey)),
        );
        device.opener.failRemovals(true);

        final second = await device.start();

        expect(second is Ok, isTrue);
      });

      test(
        'does not wait for ever for an engine that does not answer',
        () async {
          final device = _Device(parent);
          device.opener.hangOpens(true);

          final failed = await device.start(timeoutMillis: 20);

          expect(failed, equals(_unavailable(DatabaseFailureReason.open)));
        },
      );

      test('reports a schema that cannot be brought up to date, '
          'and closes the database', () async {
        final device = _Device(parent);
        final broken = Migration(
          version: schema.migrations.length + 1,
          statements: const ['INSERT INTO nowhere VALUES (1)'],
        );

        final failed = await device.start(
          migrations: [...schema.migrations, broken],
        );

        expect(failed, equals(_unavailable(DatabaseFailureReason.migration)));
        expect(device.opener.opened, equals(1));
        expect(device.opener.closed, equals(1));
      });

      test('closes the database of a newer version of the app '
          'that it leaves alone', () async {
        final device = _Device(parent);
        final newer = Migration(
          version: schema.migrations.length + 1,
          statements: const ['CREATE TABLE later (id INTEGER)'],
        );
        final future = await device.start(
          migrations: [...schema.migrations, newer],
        );
        await (future as Ok<BoardroomDatabase, DatabaseUnavailable>).value
            .close();
        final openedBefore = device.opener.opened;
        final closedBefore = device.opener.closed;

        await device.start();

        expect(
          device.opener.closed - closedBefore,
          equals(device.opener.opened - openedBefore),
        );
      });

      test('closes the connection of a file that does not unlock, '
          'and of one the engine cannot encrypt', () async {
        final rejected = _Device(parent);
        await (await _started(rejected)).close();
        rejected.storage.seed(
          SecureStorageKey.databaseKey.value,
          formatKeyState(KeyState(generation: 0, key: _otherKey)),
        );
        final openedBefore = rejected.opener.opened;
        final closedBefore = rejected.opener.closed;
        await _started(rejected);

        final plain = _Device(parent);
        plain.opener.setCipher(available: false);
        await plain.start();

        // The first one is closed, the second is the new database, which stays
        // open.
        expect(
          (rejected.opener.opened - openedBefore) -
              (rejected.opener.closed - closedBefore),
          equals(1),
        );
        expect(plain.opener.opened, equals(1));
        expect(plain.opener.closed, equals(1));
      });

      test('reports a database written by a more recent version of the app, '
          'and leaves it alone', () async {
        final device = _Device(parent);
        final newer = Migration(
          version: schema.migrations.length + 1,
          statements: const ['CREATE TABLE later (id INTEGER)'],
        );
        final future = await device.start(
          migrations: [...schema.migrations, newer],
        );
        await (future as Ok<BoardroomDatabase, DatabaseUnavailable>).value
            .close();

        final failed = await device.start();

        expect(
          failed,
          equals(_unavailable(DatabaseFailureReason.databaseIsNewer)),
        );
        final reopened = await device.start(
          migrations: [...schema.migrations, newer],
        );
        expect(reopened is Ok, isTrue);
        expect(device.monitoring.logs, isEmpty);
      });
    });

    // These have no React Native scenario: there the engine was a stand-in,
    // and the connection and the list of migrations were not the same seams.
    group('when the engine misbehaves', () {
      test(
        'does not wait for ever for an unlock that does not answer',
        () async {
          final device = _Device(parent);
          device.opener.hangStatementsMatching('PRAGMA key');

          final failed = await device.start(timeoutMillis: 20);

          expect(failed, equals(_unavailable(DatabaseFailureReason.open)));
          expect(device.opener.closed, equals(1));
          expect(device.monitoring.errors, isEmpty);
        },
      );

      test('closes the connection that cannot be set up, '
          'and reports that the file cannot be opened', () async {
        final device = _Device(parent);
        device.opener.failStatementsMatching(connectionPragmas);

        final failed = await device.start();

        expect(failed, equals(_unavailable(DatabaseFailureReason.open)));
        expect(device.opener.opened, equals(1));
        expect(device.opener.closed, equals(1));
        expect(device.opener.removed, isEmpty);
      });

      test('survives a connection that cannot be set up '
          'and does not close', () async {
        final device = _Device(parent);
        device.opener
          ..failStatementsMatching(connectionPragmas)
          ..failCloses(true);

        final failed = await device.start();

        expect(failed, equals(_unavailable(DatabaseFailureReason.open)));
      });

      final invalidLists = <(String, List<Migration>)>[
        (
          'a gap',
          [
            const Migration(version: 1, statements: []),
            const Migration(version: 3, statements: []),
          ],
        ),
        ('no migration at all', const []),
      ];
      for (final (name, list) in invalidLists) {
        test('refuses $name in the list of migrations, '
            'before touching the file', () async {
          final device = _Device(parent);

          final failed = await device.start(migrations: list);

          expect(failed, equals(_unavailable(DatabaseFailureReason.migration)));
          expect(device.opener.closed, equals(1));
          expect(device.opener.removed, isEmpty);
        });
      }
    });

    group('the errors and the options', () {
      test('tell the reason a database cannot be had, and nothing else', () {
        const error = DatabaseUnavailable(DatabaseFailureReason.keyStorage);

        expect(error.code, equals('databaseUnavailable'));
        expect(error.reason, equals(DatabaseFailureReason.keyStorage));
        expect('$error', equals('DatabaseUnavailable(keyStorage)'));
        expect(
          error,
          equals(const DatabaseUnavailable(DatabaseFailureReason.keyStorage)),
        );
        expect(
          error.hashCode,
          equals(
            const DatabaseUnavailable(DatabaseFailureReason.keyStorage)
                .hashCode,
          ),
        );
        expect(
          error,
          isNot(equals(const DatabaseUnavailable(DatabaseFailureReason.open))),
        );
      });

      test('are the same with another source of bits, '
          'another list of migrations or another time limit', () {
        final device = _Device(parent);
        final options = ProtectedDatabaseOptions(
          opener: device.opener,
          storage: device.storage,
          randomBytes: secureRandomBytes,
          monitoring: device.monitoring,
          name: 'boardroom.db',
          migrations: schema.migrations,
          databaseFactory: createBoardroomDatabase,
        );
        Future<Uint8List> zeros(int count) async => Uint8List(count);

        final changed = options.copyWith(
          randomBytes: zeros,
          migrations: const [],
          timeoutMillis: 5,
        );

        expect(changed.randomBytes, same(zeros));
        expect(changed.migrations, isEmpty);
        expect(changed.timeoutMillis, equals(5));
        expect(changed.opener, same(options.opener));
        expect(changed.storage, same(options.storage));
        expect(changed.monitoring, same(options.monitoring));
        expect(changed.name, equals('boardroom.db'));
        final unchanged = options.copyWith();
        expect(unchanged.randomBytes, same(options.randomBytes));
        expect(unchanged.migrations, same(options.migrations));
        expect(unchanged.timeoutMillis, isNull);
      });
    });
  });
}
