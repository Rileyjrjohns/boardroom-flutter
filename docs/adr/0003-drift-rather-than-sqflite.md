# 0003. drift rather than sqflite, with SQLite3MultipleCiphers and modular generation

- Status: Accepted
- Related: [0001](0001-feature-first-hexagonal-architecture-with-links-inverted-through-the-composition.md)

## Context

The offline behaviour needs a local database: the cache of the meetings and of the documents, and the vote outbox, which must neither lose a vote nor count it twice. The data is confidential (board papers), so the file is encrypted at rest with a key held in the keychain or keystore, as in the React Native app (expo-sqlite built with SQLCipher). The tables belong to features, but a feature may not import `lib/app` ([0001](0001-feature-first-hexagonal-architecture-with-links-inverted-through-the-composition.md)), and a database is one file.

## Decision

- **drift for the tables and the queries.** Tables are Dart classes and queries are checked at build time. `drift_dev` generates the code (`*.drift.dart`, not committed). The adapters (`DriftMeetingCache`, `DriftVoteOutbox`...) work against a `GeneratedDatabase` and the tables they own, so they are tested on an in-memory database.
- **Encryption with SQLite3MultipleCiphers through `package:sqlite3`.** `pubspec.yaml` asks the build hook of `sqlite3` for `source: sqlite3mc` (`hooks.user_defines`). The `sqlcipher` cipher of that library reads and writes SQLCipher 4 files: `lib/core/infrastructure/persistence/unlock_database.dart` selects it (`PRAGMA cipher = 'sqlcipher'`) and applies the key. The key is made by a secure random source and kept in the secure storage (`database_key.dart`, `random_key.dart`); if the engine has no encryption, nothing is stored (`encryptionUnavailable`) rather than stored in clear. `test/core/infrastructure/persistence/encrypted_sqlite_test.dart` opens an encrypted file on the machine that runs the tests.
- **Modular code generation.** `build.yaml` replaces drift's default builder with `drift_dev:analyzer` and `drift_dev:modular`. Each feature declares its tables and their names (`lib/features/<feature>/infrastructure/persistence/tables.dart`, `schema.dart`) and the generator writes a `tables.drift.dart` beside each. `lib/app/persistence/boardroom_database.dart` lists the tables of the whole file, and `migrations.dart` keeps the history. The machinery in `lib/core/infrastructure/persistence` (`openProtectedDatabase`, `Migration`, `migrationStrategyOf`) knows no database of the app: the composition gives it the migrations and a factory.
- **Migrations are SQL kept as data**, with the `user_version` pragma, and a file written by a newer version is refused (`databaseIsNewer`).

## Consequences

- Queries are typed and a schema change that breaks one fails the build.
- The split keeps the graph of [0001](0001-feature-first-hexagonal-architecture-with-links-inverted-through-the-composition.md): `votes` cannot see the tables of `meetings`, yet one encrypted file serves all four features.
- The library is downloaded by the build hook at the first build, test run or `dart run`, and checked against a hash held by the package. A machine with no network at that moment cannot build. Nothing is installed by hand.
- The `dev` configuration does not use this database (it keeps its caches and outbox in memory), so the encrypted path runs in the `http` configuration and in the tests, as the demo of React Native keeps its encrypted SQLite for the `http` configuration.
- The encryption is verified on the host and by tests; it has not been audited on a device by looking at the file.

## Alternatives considered

- **sqflite.** Widely used, raw SQL strings and no build-time check. Encryption needs the separate `sqflite_sqlcipher`, which carries its own native SQLCipher build, and the tests would need an FFI shim to run on a host.
- **sqflite_sqlcipher or `sqlcipher_flutter_libs` with drift.** Works, but ships a second native SQLite on top of the platform one. The build hook of `sqlite3` brings one library for iOS, Android and the test host, so the tests run the same engine as the app.
- **Isar, Hive, ObjectBox.** No SQL: the outbox and the cache need transactions and ordered reads that SQLite gives directly, and the migrations of the two apps would stop being comparable.
- **One drift file for the whole app** (the default generator). The tables would be reachable only through `lib/app`, which the features cannot import.
