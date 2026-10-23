# Parity of the infrastructure

How the infrastructure folders of `lib/` (`lib/core/infrastructure`, `lib/features/<feature>/infrastructure`, and `lib/app` for the simulated world and the database) and their tests (`test/core/infrastructure`, `test/features/<feature>/infrastructure`, `test/app`, `test/support/infrastructure`) map to `src/infrastructure` of the React Native app (the commit of [`RN_COMMIT`](RN_COMMIT)). The rules of [`../porting.md`](../porting.md) apply: same names (in Dart case), same behaviour, same error codes, same monitoring events, same limits, and the tests of a file keep their full names wherever the scenario exists in Dart. The points where Dart forced a choice are in [`open-questions.md`](open-questions.md), section "Infrastructure (step 3)".

`tool/scenario_parity.dart` only reads `src/domain` and `src/application`, so the table below was drawn up by running the same extractor (`tool/ts_test_names.dart`) on the infrastructure test files and comparing the full names with the ones `flutter test --machine` lists for the infrastructure folders. A name that contains `%j` or a table computed at run time (`fixtureTimeline`) was matched as a pattern. The table is kept by hand from here on. In the tables, the Dart columns give the paths under `lib/` (the files) and under `test/` (the test files), so that the place of each file in the feature layout of [`../porting.md`](../porting.md) is visible: the shared kernel is `core`, what belongs to one feature is under `features/<feature>`, and the simulated world of the development build and the database of the whole file are under `app`.

This page covers the whole of step 3, in five parts:

1. the foundations (shared helpers, clock, monitoring, the wire classes (DTOs), the loader of the fixtures, files, documents, PDF and secure storage) and the fixture server (the simulated server, the seed, `MockApi` and the dio adapter that stands in for the network), in the first two tables;
2. the device adapters and the in-memory adapters (biometrics, connectivity, the platform bundle, the adapters of the mock configuration);
3. the HTTP client and repositories;
4. the persistence (drift, the encrypted database, the caches and the outbox);
5. the contract suites: which adapter of which port runs which suite, and the totals of the step, at the end of the page.

Out of scope for step 3: `native/NativeScreenProtection.test.ts` (36 tests, the screen protection plugin: they are ported in step 4, see [Screen protection plugin (step 4)](#screen-protection-plugin-step-4)), and the tests of the standalone Node program of `tooling/mock-api` (11 tests, the program is not ported: the development build talks to the dio adapter in process).

## Files

| React Native (`src/infrastructure/`) | Dart (under `lib/`) | Note |
| --- | --- | --- |
| `shared/attempt.ts` | `core/infrastructure/shared/attempt.dart` | `ATTEMPT_FAILURE` is `AttemptFailureKind` |
| `shared/clonePlain.ts` | (none) | Entities are immutable |
| `shared/issuePaths.ts` | `core/infrastructure/shared/issue_paths.dart` | Takes the paths, not a zod error |
| `shared/rejectionSchemas.ts` | `features/votes/infrastructure/rejection_schemas.dart` | Hand-written discriminated union (`VotingErrorWire`, `UndeliverableWire`) |
| `shared/results.ts` | `core/infrastructure/shared/results.dart` | |
| `shared/serialQueue.ts` | `core/infrastructure/shared/serial_queue.dart` | |
| `shared/sha256.ts` | `core/infrastructure/shared/sha256.dart` | Package `crypto` |
| `shared/subscribers.ts` | `core/infrastructure/shared/subscribers.dart` | |
| `shared/valid.ts` | `core/infrastructure/shared/valid.dart` | |
| `clock/sleep.ts` | `core/infrastructure/clock/sleep.dart` | |
| `clock/SystemClock.ts` | `core/infrastructure/clock/system_clock.dart` | |
| `monitoring/ConsoleMonitoring.ts` | `core/infrastructure/monitoring/console_monitoring.dart` | |
| `monitoring/SentryMonitoring.ts` | `core/infrastructure/monitoring/sentry_monitoring.dart` | Disabled, no SDK: [`../monitoring.md`](../monitoring.md) |
| `http/protocol.ts` | `core/infrastructure/http/protocol.dart` | |
| `http/HttpClient.ts` (`BearerToken`, `BearerTokenSource`) | `core/infrastructure/http/http_client.dart` | These two types come from the foundations; the client is in the section "HTTP client and repositories" below |
| `http/dto/wire.ts` | `core/infrastructure/http/dto/wire.dart` | Instants, `decodeWire` |
| `http/dto/documentDto.ts` | `features/documents/infrastructure/dto/document_dto.dart` | `json_serializable` |
| `http/dto/meetingDto.ts` | `features/meetings/infrastructure/dto/meeting_dto.dart` | `json_serializable` |
| `http/dto/sessionDto.ts` | `features/auth/infrastructure/dto/session_dto.dart` | `json_serializable` |
| `http/dto/voteDto.ts` | `features/votes/infrastructure/dto/vote_dto.dart` | `json_serializable` |
| `in-memory/fixtures/fixtureSchemas.ts` | `app/dev/in_memory/fixtures/fixture_schemas.dart` | `json_serializable` |
| `in-memory/fixtures/loadFixtures.ts` | `app/dev/in_memory/fixtures/load_fixtures.dart` | Takes the text of the files |
| `in-memory/fixtures/bundledFixtures.ts` | `app/dev/in_memory/fixtures/bundled_fixtures.dart` | Reads the Flutter assets |
| `in-memory/InMemoryAuthSession.ts` (`DemoAccount`) | `app/dev/in_memory/in_memory_auth_session.dart` | Only `DemoAccount`; the in-memory step adds the class |
| `in-memory/InMemoryBackend.ts` | `app/dev/in_memory/in_memory_backend.dart` | `ServerContent` (from the foundations), `Caller`, `AuthSessionCaller`, `InMemoryBackend`, `ServedDocumentContent`, `ServerContentError`. Errors are the common types of the ports (`GatewayError`, `RepositoryError`, `AppError`) |
| `in-memory/SimulatedNetwork.ts` | `app/dev/in_memory/simulated_network.dart` | Named booleans (`setOnline(online: false)`) |
| `in-memory/seed.ts` | `app/dev/in_memory/seed.dart` | `buildSeed` is a `Future` (the fixtures are assets); `DEMO_PASSWORD` is `demoPassword` |
| `mock-api/MockApi.ts` | `app/dev/fixture_server/mock_api.dart` | Over `ApiRequest` and `ApiResponse` (`lib/app/dev/fixture_server/api_message.dart`) instead of `Request` and `Response` |
| (MSW, in the tests of React Native) | `app/dev/fixture_server/fixture_server_adapter.dart` | A dio `HttpClientAdapter` in front of `MockApi`, in `lib/` because the development build uses it. It also holds the limit of 64 KiB on a request, which is in `tooling/mock-api/server.ts` in React Native |
| `tooling/mock-api/server.ts` (`createMockApiServer`) | `app/dev/fixture_server/fixture_server.dart` | `FixtureServer.create`, without the Node server (the build talks to the adapter in process); the standalone program is not ported |
| `files/FileStore.ts` | `core/infrastructure/files/file_store.dart` | |
| `files/ExpoFileVolume.ts` | `core/infrastructure/files/io_file_volume.dart` | `dart:io` |
| `files/createExpoFileStore.ts` | `core/infrastructure/files/create_device_file_store.dart` | `path_provider` |
| `documents/documentContent.ts` | `features/documents/infrastructure/document_content.dart` | |
| `documents/storeDocumentContent.ts` | `features/documents/infrastructure/store_document_content.dart` | |
| `pdf/createDocumentPdf.ts` | `app/dev/pdf/create_document_pdf.dart` | |
| `pdf/pdfSignature.ts` | `features/documents/infrastructure/pdf_signature.dart` | |
| `secure-storage/SecureStorage.ts` | `core/infrastructure/secure_storage/secure_storage.dart` | `SECURE_STORAGE_KEY` is `SecureStorageKey` |
| `secure-storage/ExpoSecureStorage.ts` | `core/infrastructure/secure_storage/device_secure_storage.dart` | `flutter_secure_storage` |
| `secure-storage/SessionVault.ts` | `features/auth/infrastructure/session_vault.dart` | |

## Test support

| React Native (`src/infrastructure/testing/`) | Dart (`test/support/infrastructure/`) | Note |
| --- | --- | --- |
| `sleep.ts` | `sleep.dart` | |
| `MemorySecureStorage.ts` | `memory_secure_storage.dart` | Counts its calls (`getCalls`, `setCalls`, `removeCalls`) where React Native spies on them |
| `FaultyFileVolume.ts` | `faulty_file_volume.dart` | Fails with a `FileSystemException` of error number 5 (`EIO`) |
| `NodeFileVolume.ts` | `lib/core/infrastructure/files/io_file_volume.dart` and `test_files.dart` | The volume of the tests is the real one, over a temporary directory |
| `testFiles.ts`, `NodeSqlite.ts` (`temporaryDirectory`, `freshDirectory`) | `test_files.dart` | |
| `fixtureFiles.ts` | `fixture_files.dart` | Plus `DecodedFixtures`, the files parsed to be broken in place |
| `documentDevice.ts` | `document_device.dart` | For the document cache contract |
| (none) | `memory_file_volume.dart` | A volume in memory, for tests that need no disk |
| (none) | `encrypted_test_database.dart` | `openEncryptedTestDatabase`: the database as `openProtectedDatabase` gives it (a key made and kept in a keychain in memory, a file encrypted for real), as a `TestDatabase` whose `reopen` is a new start of the app and whose statements can be made to fail through an opener that wraps the executor; for the third run of the cache and outbox contract suites |
| `testServer.ts` | `test_server.dart` | `createTestServer`, with the real `InMemoryAuthSession` as the session of the device and the three in-memory repositories (`meetings`, `documents`, `votes`), as in React Native |
| `serverSetups.ts` | `server_setups.dart` | `meetingsServerSide`, `documentsServerSide`, `votesServerSide` |
| `httpWorld.ts` | `http_world.dart` | `installFixtureServer` (MSW's `installMockApi`), `createHttpServerSide`; `createHttpWorld` is in `test/support/infrastructure/http_adapters_world.dart` (section "HTTP client and repositories" below) |
| `nodeRandomBytes.ts`, `NodeSqlite.ts`, `fake*.ts`... | (not in this part) | The persistence and HTTP parts of the step |

## Tests

"RN" is the number of tests of the React Native file once its `each` tables are expanded, "Dart" the number of tests of the Dart file. Every RN test that is not listed under "Not ported" has a Dart test with the identical full name.

| React Native test file | Dart test file (under `test/`) | RN | Dart | Not ported (RN scenario: reason) |
| --- | --- | --- | --- | --- |
| `shared/attempt.test.ts` | `core/infrastructure/shared/attempt_test.dart` | 14 | 13 | `describeFailure ... about a code that is not a string`, `... about an error code that is not an integer`: JavaScript error objects with a `code` property, Dart exceptions are typed (the `code` of a `PlatformException` is the one that is kept, step 4: the two scenarios about a code that is or is not written like one run on it); `... says nothing specific about undefined`: Dart has no `undefined` (`null` is the row "null") |
| `shared/clonePlain.test.ts` | (none) | 3 | 0 | The 3 scenarios: `clonePlain` is not ported, Dart values are immutable |
| `shared/issuePaths.test.ts` | `core/infrastructure/shared/issue_paths_test.dart` | 3 | 3 | |
| `shared/rejectionSchemas.test.ts` | `features/votes/infrastructure/rejection_schemas_test.dart` | 29 | 30 | |
| `shared/results.test.ts` | `core/infrastructure/shared/results_test.dart` | 3 | 3 | |
| `shared/serialQueue.test.ts` | `core/infrastructure/shared/serial_queue_test.dart` | 5 | 5 | |
| `shared/sha256.test.ts` | `core/infrastructure/shared/sha256_test.dart` | 19 | 19 | |
| `shared/subscribers.test.ts` | `core/infrastructure/shared/subscribers_test.dart` | 5 | 5 | |
| `shared/valid.test.ts` | `core/infrastructure/shared/valid_test.dart` | 2 | 2 | |
| `clock/sleep.test.ts` | `core/infrastructure/clock/sleep_test.dart` | 1 | 1 | |
| `clock/SystemClock.test.ts` | `core/infrastructure/clock/system_clock_test.dart` | 8 | 8 | |
| `monitoring/ConsoleMonitoring.test.ts` | `core/infrastructure/monitoring/console_monitoring_test.dart` | 7 | 8 | The default sink writes the line with `print`, which has one channel: its line starts with the word of the channel (`info`, `warn`, `error`), and the test `writes to the global console by default` expects it |
| `monitoring/SentryMonitoring.test.ts` | `core/infrastructure/monitoring/sentry_monitoring_test.dart` | 38 | 38 | |
| `http/dto/documentDto.test.ts` | `features/documents/infrastructure/dto/document_dto_test.dart` | 15 | 15 | |
| `http/dto/meetingDto.test.ts` | `features/meetings/infrastructure/dto/meeting_dto_test.dart` | 50 | 50 | |
| `http/dto/sessionDto.test.ts` | `features/auth/infrastructure/dto/session_dto_test.dart` | 32 | 33 | |
| `http/dto/voteDto.test.ts` | `features/votes/infrastructure/dto/vote_dto_test.dart` | 18 | 18 | |
| `http/dto/wire.test.ts` | `core/infrastructure/http/dto/wire_test.dart` | 24 | 32 | |
| `in-memory/fixtures/fixtureTimeline.test.ts` | `app/dev/in_memory/fixtures/fixture_timeline_test.dart` | 6 (4 tables computed at run time, 250 tests) | 250 | |
| `in-memory/fixtures/loadFixtures.test.ts` | `app/dev/in_memory/fixtures/load_fixtures_test.dart`, `app/dev/in_memory/fixtures/bundled_fixtures_test.dart`, and `app/dev/in_memory/seed_test.dart` for the two scenarios that need the seed and the simulated server | 127 | 127 | |
| `files/FileStore.test.ts` | `core/infrastructure/files/file_store_test.dart` | 44 | 44 | |
| `files/ExpoFileVolume.test.ts` | `core/infrastructure/files/io_file_volume_test.dart` | 14 | 14 | `... is a directory of the caches of the app for the caches storage` and `... of the private storage of the app for the private storage`: Expo-specific (`Paths.cache`), the choice by platform is `createDeviceFileStore chooses the storage by the platform`; `... says its location with a slash at the end, whether or not the module does`: Expo-specific, `Directory.uri` always ends with a slash (`is the location of its directory, with a slash at the end`). The groups are named `IoFileVolume` and `createDeviceFileStore` |
| `secure-storage/ExpoSecureStorage.test.ts` | `core/infrastructure/secure_storage/device_secure_storage_test.dart` | 3 | 8 | The group is named `DeviceSecureStorage`. The native side of the plugin is replaced on its channel, which keeps the items in memory and records the options of every `write`, `read` and `delete`, so the options the adapter passes are checked on the three calls, on iOS, macOS and Android (as the React Native test checks the options passed to the module) |
| `secure-storage/SessionVault.test.ts` | `features/auth/infrastructure/session_vault_test.dart` | 28 | 29 | |
| `pdf/createDocumentPdf.test.ts` | `app/dev/pdf/create_document_pdf_test.dart` | 27 | 28 | |
| `testing/sleep.test.ts` | `support/infrastructure/sleep_test.dart` | 2 | 2 | |
| `in-memory/SimulatedNetwork.test.ts` | `app/dev/in_memory/simulated_network_test.dart` | 10 | 12 | |
| `in-memory/seed.test.ts` | `app/dev/in_memory/seed_test.dart` | 122 | 126 | |
| `in-memory/InMemoryBackend.test.ts` | `app/dev/in_memory/in_memory_backend_test.dart` | 54 | 55 | `... refuses a page limit of 1.5, which the domain does not accept` and `... of NaN ...`: `PageRequest.limit` is an `int`, such a limit cannot be written. The tests that go through a repository call the backend the repositories delegate to; the two tests of `content` that check the file the document repository writes run against `InMemoryDocumentRepository` of `createTestServer`. The two tests of copies check immutability (see open-questions.md) |
| `mock-api/MockApi.test.ts` | `app/dev/fixture_server/mock_api_test.dart` | 76 | 81 | |

789 React Native tests, 776 with a Dart test of the same name, 13 not ported (the reasons above).

## Dart tests with no React Native scenario

These tests check something that exists only in Dart, or code that React Native has no test file for.

| Dart test file (under `test/`) | Tests | What |
| --- | --- | --- |
| `core/infrastructure/shared/attempt_test.dart` | 2 | `describeFailure` reads the error number of a `FileSystemException` (the two tests on a `PlatformException` are the scenarios of the table above) |
| `features/votes/infrastructure/rejection_schemas_test.dart` | 1 | The failure names the place of the flaw and no value |
| `features/auth/infrastructure/dto/session_dto_test.dart` | 1 | The wire classes never print the token nor the password |
| `core/infrastructure/http/dto/wire_test.dart` | 8 | The parser and the writer of instants (impossible days, 24:00:00, offsets, the year range, `-000001`), `decodeWire` on a body that is not an object |
| `app/dev/in_memory/fixtures/load_fixtures_test.dart` | 2 | A text that is not JSON; the seed prints no password |
| `core/infrastructure/files/io_file_volume_test.dart` | 3 | The location of the volume, a location it is told to say, the choice of the storage by platform |
| `core/infrastructure/secure_storage/device_secure_storage_test.dart` | 5 | Forgetting a key that is not there; the options of `write`, `read` and `delete` on iOS and on macOS (the service of the app, readable on this device only); `resetOnError` off on Android for the three calls; the error of a read reaches the caller |
| `core/infrastructure/files/device_folders_test.dart` | 4 | The documents go to the caches folder on iOS and to the support folder on Android, the database to the support folder, and no other folder (documents, library, temporary) is asked of `path_provider` |
| `core/infrastructure/monitoring/console_monitoring_test.dart` | 1 | The three channels are told apart in the lines the default sink prints |
| `features/auth/infrastructure/session_vault_test.dart` | 1 | The vault never prints the token |
| `app/dev/pdf/create_document_pdf_test.dart` | 1 | `hasPdfSignature` |
| `core/infrastructure/http/protocol_test.dart` | 7 | The routes (percent-encoding, number of segments), the headers, the limits, the transient statuses (no test file in React Native) |
| `features/documents/infrastructure/document_content_test.dart` | 12 | `documentFileName`, `storeDocumentContent`, `contentExists`, `deleteContent` (covered by the repository tests in React Native) |
| `support/infrastructure/memory_file_volume_test.dart` | 3 | The volume in memory behaves like a volume of a device under the store |
| `core/infrastructure/persistence/encrypted_sqlite_test.dart` | 8 | SQLite3MultipleCiphers encrypts a database file with `PRAGMA key`, through `sqlite3` and `drift` (no counterpart: React Native uses `expo-sqlite`) |
| `app/dev/in_memory/simulated_network_test.dart` | 2 | The subscribers are told when the connection goes off and comes back, and only then; a subscriber that throws does not stop the others |
| `app/dev/in_memory/seed_test.dart` | 2 | `buildSeed` gives the data of the fixtures bundled with the app, the same for the same instant |
| `app/dev/in_memory/in_memory_backend_test.dart` | 3 | The caller from an `AuthSession`, a session that cannot be read is nobody, equality and printing of the content |
| `app/dev/fixture_server/mock_api_test.dart` | 5 | The query read like a URL query (`+`, a malformed escape, a repeated name), the method and the `Authorization` header whatever their case, the codes of the error bodies |
| `app/dev/fixture_server/fixture_server_adapter_test.dart` | 15 | The adapter with a real `Dio`: JSON, bytes and `ETag`, no `Content-Length` for a 204, an identifier and a cursor percent-encoded, the limit of 64 KiB (413), cancellation, the receive timeout, the logger, a failing API answered 500 |
| `app/dev/fixture_server/fixture_server_test.dart` | 19 | `FixtureServer.create` and the fixtures through dio: sign in, 24 upcoming and 42 past meetings by page, a vote and its replay, a PDF, 503 while the network is cut, expiry on the clock, defaults, `randomToken`; the HTTP client, session and meeting repository of the app composed over the bundled fixtures, as the development build composes them |
| `support/infrastructure/http_world_test.dart` | 13 | The support code of the HTTP tests: recorded requests, offline, delay, a server that never answers, an answer chosen by the test, another host refused, the accounts and tokens of `createHttpServerSide` |

## Device adapters and in-memory adapters

The biometrics, the connectivity, the platform bundle, and the adapters of the mock configuration that React Native keeps in `in-memory/` (the session store, the biometric gate, the two caches, the outbox, the screen protection, the three repositories). The contract suite of each port runs against each of them, as in React Native; the choice of the ones that are kept is in [`open-questions.md`](open-questions.md), section "Infrastructure (step 3)". This part has its own totals; the totals of the whole step are at the end of the page.

### Files

| React Native (`src/infrastructure/`) | Dart (under `lib/`) | Note |
| --- | --- | --- |
| `biometrics/DeviceBiometricGate.ts` | `features/auth/infrastructure/biometrics/device_biometric_gate.dart` | `LocalAuthenticationApi` takes an `AuthenticationPrompt` and answers a `LocalAuthenticationResult`; the outcomes are the enum `LocalAuthenticationError`, the level the enum `BiometricsSecurityLevel` |
| `biometrics/ExpoLocalAuthentication.ts` | `features/auth/infrastructure/biometrics/device_local_authentication.dart` | `local_auth`; the exceptions of the plugin become the outcomes the gate understands |
| `connectivity/ExpoConnectivity.ts` | `core/infrastructure/connectivity/device_connectivity.dart` | `DeviceConnectivity`, with `NetworkSnapshot`, `NetworkStateApi` and `statusOf` |
| `connectivity/ExpoNetworkState.ts` | `core/infrastructure/connectivity/connectivity_plus_network_state.dart` | `connectivity_plus`; `snapshotOf` reads its list of connections |
| `connectivity/SimulatedConnectivity.ts` | `app/dev/in_memory/simulated_connectivity.dart` | Over a `NetworkControl` |
| `device/DevicePlatform.ts` | `app/device/device_platform.dart` | Adds `databaseOpener` and `randomBytes`; the native side of the screen protection is the plugin of step 4 (`features/documents/infrastructure/native`) |
| `device/createExpoPlatform.ts` | `app/device/create_device_platform.dart` | A `Future`: the folder of the databases is asked of the platform |
| `in-memory/InMemoryAuthSession.ts` | `app/dev/in_memory/in_memory_auth_session.dart` | `DemoAccount` is the one of the foundations, in the same file |
| `in-memory/InMemoryBiometricGate.ts` | `app/dev/in_memory/in_memory_biometric_gate.dart` | |
| `in-memory/InMemoryMeetingCache.ts` | `features/meetings/infrastructure/in_memory_meeting_cache.dart` | No copies: the values are immutable |
| `in-memory/InMemoryDocumentCache.ts` | `features/documents/infrastructure/in_memory_document_cache.dart` | No copies: the values are immutable |
| `in-memory/InMemoryVoteOutbox.ts` | `features/votes/infrastructure/in_memory_vote_outbox.dart` | No copies: the values are immutable |
| `in-memory/InMemoryScreenProtection.ts` | `features/documents/infrastructure/in_memory_screen_protection.dart` | |
| `in-memory/InMemoryMeetingRepository.ts` | `app/dev/in_memory/in_memory_meeting_repository.dart` | |
| `in-memory/InMemoryDocumentRepository.ts` | `app/dev/in_memory/in_memory_document_repository.dart` | |
| `in-memory/InMemoryVoteRepository.ts` | `app/dev/in_memory/in_memory_vote_repository.dart` | |
| `testing/FakeNetworkState.ts` | `test/support/infrastructure/fake_network_state.dart` | The state of the network a test drives |

### Tests

| React Native test file | Dart test file (under `test/`) | RN | Dart | Not ported (RN scenario: reason) |
| --- | --- | --- | --- | --- |
| `biometrics/DeviceBiometricGate.test.ts` | `features/auth/infrastructure/biometrics/device_biometric_gate_test.dart` | 45 | 41 | `... authenticate does not take a truthy value that is not true for a success`, `... the number 1 ...`, `... nothing ...`, `... null ...`: `LocalAuthenticationResult.success` is a `bool` and the platform layer answers a result, never nothing; JavaScript truthiness does not exist in Dart. The object without `success` and the codes that are property names (`constructor`, `__proto__`...) remain, as codes read as text |
| `biometrics/ExpoLocalAuthentication.test.ts` | `features/auth/infrastructure/biometrics/device_local_authentication_test.dart` | 2 | 25 | The group is named `DeviceLocalAuthentication` |
| `connectivity/ExpoConnectivity.test.ts` | `core/infrastructure/connectivity/device_connectivity_test.dart` | 27 | 27 | The group is named `DeviceConnectivity`. The nine `statusOf` rows end with the status they give (`as online`) where the React Native names are computed at run time |
| `connectivity/ExpoNetworkState.test.ts` | `core/infrastructure/connectivity/connectivity_plus_network_state_test.dart` | 2 | 6 | The group is named `ConnectivityPlusNetworkState` |
| `connectivity/SimulatedConnectivity.test.ts` | `app/dev/in_memory/simulated_connectivity_test.dart` | 11 | 11 | |
| `device/createExpoPlatform.test.ts` | `app/device/create_device_platform_test.dart` | 2 | 3 | The group is named `createDevicePlatform` |
| `in-memory/InMemoryAuthSession.test.ts` | `app/dev/in_memory/in_memory_auth_session_test.dart` | 19 | 19 | |
| `in-memory/InMemoryBiometricGate.test.ts` | `app/dev/in_memory/in_memory_biometric_gate_test.dart` | 4 | 4 | |
| `in-memory/InMemoryDocumentCache.test.ts` | `features/documents/infrastructure/in_memory_document_cache_test.dart` | 32 | 30 | The two scenarios of the contract about changing a document after it was saved and after it was read: a document has no setter in Dart (the same two are in [`exceptions.md`](exceptions.md) for the fake) |
| `in-memory/InMemoryMeetingCache.test.ts` | `features/meetings/infrastructure/in_memory_meeting_cache_test.dart` | 34 | 33 | `... hands out a new object at every read`: the cache shares the immutable value, as the fake does (in [`exceptions.md`](exceptions.md)) |
| `in-memory/InMemoryRepositories.test.ts` | `app/dev/in_memory/in_memory_repositories_test.dart` | 54 | 54 | |
| `in-memory/InMemoryScreenProtection.test.ts` | `features/documents/infrastructure/in_memory_screen_protection_test.dart` | 12 | 12 | |
| `in-memory/InMemoryVoteOutbox.test.ts` | `features/votes/infrastructure/in_memory_vote_outbox_test.dart` | 54 | 51 | The three scenarios of the contract about changing a vote or a reason after it was given: a vote has no setter in Dart (the same three are in [`exceptions.md`](exceptions.md) for the fake) |

298 React Native tests, 288 with a Dart test of the same name, 10 not ported (the reasons above). The contract suites of the caches and of the outbox show their groups about a failing statement, a reopened store and an unreadable entry as skipped for the adapters in memory, as in React Native (`IN_MEMORY_STORE`).

### Dart tests with no React Native scenario

| Dart test file (under `test/`) | Tests | What |
| --- | --- | --- |
| `features/auth/infrastructure/biometrics/device_local_authentication_test.dart` | 23 | The enrolment counts a biometric that is not `weak` and nothing else (nothing, only `weak`, a face, a fingerprint, a strong one that Android also reports as `weak`); each exception of `local_auth` becomes the outcome the gate understands (all 14, and a test that the table is complete); the passcode and the fallback button of iOS in the prompt; what `false` means; anything else the plugin throws goes to the gate |
| `core/infrastructure/connectivity/connectivity_plus_network_state_test.dart` | 4 | `snapshotOf` reads no connection, wifi, a mobile network and several connections |
| `app/device/create_device_platform_test.dart` | 1 | The databases are in a folder of the private storage |
| `features/auth/infrastructure/biometrics/local_authentication_values_test.dart` | 6 | `PromptText`, `AuthenticationPrompt` and `LocalAuthenticationResult` compare by what they hold and print (React Native compares plain objects); `AuthenticationPrompt` prints its level and fallback, not the text |
| `core/infrastructure/connectivity/network_snapshot_test.dart` | 2 | `NetworkSnapshot` compares by its two flags and prints a flag that is not set as null |

## HTTP client and repositories

The client over dio and the four adapters of the remote ports (`AuthSession`, `MeetingRepository`, `DocumentRepository`, `VoteRepository`). Their tests go through the fixture server's dio adapter (the counterpart of MSW), with `ScriptedAdapter` for the tests of the client itself (the counterpart of the scripted `fetch`), and the four contract suites run against them. The points where Dart forced a choice are in [`open-questions.md`](open-questions.md), section "Infrastructure (step 3)": `HttpClient` has no retry interceptor because the React Native client retries nothing.

### Files

| React Native (`src/infrastructure/`) | Dart (under `lib/`) | Note |
| --- | --- | --- |
| `http/apiBaseUrl.ts` | `core/infrastructure/http/api_base_url.dart` | |
| `http/HttpClient.ts` | `core/infrastructure/http/http_client.dart` | `HttpClient` over dio: an interceptor attaches the token (`BearerToken` and `BearerTokenSource` come from the foundations), `HttpClientOptions.adapter` replaces `fetch`, `HttpFailure` is `RequestFailed` or `RequestRejected`, `schema` is `decode`, a request is given as a function, and there is a `close()`. The types of `fetch` are not ported |
| `http/gatewayErrors.ts` | `core/infrastructure/http/gateway_errors.dart` | |
| `http/invalidResponse.ts` | `core/infrastructure/http/invalid_response.dart` | `HTTP_RESOURCE`, `CONTENT_VIOLATION` and `IDENTITY_VIOLATION` are enums; `WHOLE_BODY_PATH` is `rootPath` of `lib/core/infrastructure/shared/issue_paths.dart` |
| `http/statusCause.ts` | `core/infrastructure/http/status_cause.dart` | |
| (none) | `core/infrastructure/http/well_formed.dart` | `requireWellFormed` and `encodeUriComponent`: `encodeURIComponent` throws for a lone surrogate and `Uri.encodeComponent` does not |
| `http/HttpAuthSession.ts` | `features/auth/infrastructure/http_auth_session.dart` | |
| `http/HttpMeetingRepository.ts` | `features/meetings/infrastructure/http_meeting_repository.dart` | |
| `http/HttpDocumentRepository.ts` | `features/documents/infrastructure/http_document_repository.dart` | |
| `http/HttpVoteRepository.ts` | `features/votes/infrastructure/http_vote_repository.dart` | |

### Test support

| React Native (`src/infrastructure/testing/`) | Dart (`test/support/infrastructure/`) | Note |
| --- | --- | --- |
| `httpWorld.ts` (`createHttpWorld`, `HttpWorld`, `HttpWorldOptions`) | `http_adapters_world.dart` | The server side and the HTTP adapters of a device, built by hand as the composition root builds them. Synchronous; `HttpWorldOptions` is a class |
| (the scripted `fetch` of `HttpClient.test.ts`, `HttpClient.download.test.ts` and `HttpAdapterGuards.test.ts`) | `scripted_adapter.dart` | `ScriptedAdapter`: one answer per request (a status, headers, a body as text or chunks, a failure, silence, a body that breaks), the requests it received, and how the bodies were read. `paced` makes the chunks wait, because dio reads a body as soon as it has the headers |

### Tests

| React Native test file | Dart test file (under `test/`) | RN | Dart | Not ported (RN scenario: reason) |
| --- | --- | --- | --- | --- |
| `http/apiBaseUrl.test.ts` | `core/infrastructure/http/api_base_url_test.dart` | 41 | 41 | |
| `http/HttpClient.test.ts` | `core/infrastructure/http/http_client_test.dart` | 95 | 102 | `... the size of an answer refuses a text that is longer than the maximum when the platform gives no stream`: dio always gives a stream. The group "over the global fetch and MSW" keeps its name and runs the client over the fixture server's adapter |
| `http/HttpClient.download.test.ts` | `core/infrastructure/http/http_client_download_test.dart` | 38 | 35 | `... the answer reads a platform that gives no stream through its buffer`, `... refuses a buffer that is bigger than the maximum, though nothing said so` and `... is a network that failed when the platform gives neither a stream nor a buffer`: dio always gives a stream |
| `http/HttpAuthSession.test.ts` | `features/auth/infrastructure/http_auth_session_test.dart` | 17 | 18 | The four scenarios that mock `HttpClient.request` have the server send what the mock returned (see open-questions.md) |
| `http/HttpRepositories.test.ts` | `app/http/http_repositories_test.dart` | 66 | 66 | The contract suites of `MeetingRepository`, `DocumentRepository`, `VoteRepository` and `AuthSession` |
| `http/HttpDocumentRepository.test.ts` | `features/documents/infrastructure/http_document_repository_test.dart` | 37 | 39 | |
| `http/HttpAdapterGuards.test.ts` | `app/http/http_adapter_guards_test.dart` | 19 | 19 | |

313 React Native tests, 309 with a Dart test of the same name, 4 not ported (the reasons above).

### Dart tests with no React Native scenario

| Dart test file (under `test/`) | Tests | What |
| --- | --- | --- |
| `core/infrastructure/http/http_client_test.dart` | 8 | Nothing is retried; the connection is dropped for a success whose body nobody wants and not for one that was read; a length written as `n.0`; a body that is not UTF-8; `close`; the token is never printed; two failures compare by what they hold |
| `core/infrastructure/http/http_client_network_test.dart` | 13 | The client over the adapter dio uses on a device, against a server on this machine: the token and the headers, a redirect that is not followed, a body that grows past the limit (declared or not, compressed or not), the connection that is dropped when the body of a success, of a refusal or of an answer that is too big is not wanted (a raw socket tells), the time limit for a server that is silent or whose body never ends, a refused connection, a download. React Native tests its real `fetch` through MSW only |
| `features/auth/infrastructure/http_auth_session_test.dart` | 1 | A sign-in carries no token, and the password is in its body only |
| `features/documents/infrastructure/http_document_repository_test.dart` | 2 | A download that arrives in pieces; metadata that is not JSON |
| `features/meetings/infrastructure/http_meeting_repository_test.dart` | 6 | What is sent (the period, the limit, the cursor, an identifier percent-encoded); a page and a meeting of the wrong shape or that break a rule of the domain (no test file in React Native) |
| `features/votes/infrastructure/http_vote_repository_test.dart` | 14 | What is sent (the route, the key in a header, the token); the six voting errors of a 422; a description that is not one, or that breaks a rule; a 422 with none; the gateway errors of a 403, a 404, a 500 and a 503 (no test file in React Native) |
| `core/infrastructure/http/gateway_errors_test.dart` | 12 | `asGatewayError` and `asRepositoryError` (no test file in React Native) |
| `core/infrastructure/http/status_cause_test.dart` | 1 | `statusCause` (no test file in React Native) |
| `core/infrastructure/http/well_formed_test.dart` | 16 | `isWellFormed`, `requireWellFormed`, `encodeUriComponent` |
| `core/infrastructure/http/invalid_response_test.dart` | 6 | What `schemaViolation`, `domainViolation`, `contentViolation` and `identityViolation` tell the monitoring, and the names of `HttpResource` (no test file in React Native) |

## Persistence

The database, its key and its caches. drift stands where React Native has its own thin layer over the SQL engine (`SqlDatabase`), so the adapters are written against a drift `GeneratedDatabase` and the tables their feature owns, and `BoardroomDatabase` (in `lib/app/persistence`) is the drift database of the whole file that lists those tables; the classes `Sqlite…` are `Drift…`, and the tests of a class keep the name of its Dart class in their full names (`SqliteMeetingCache honours the MeetingCache contract …` is `DriftMeetingCache honours the MeetingCache contract …`). The reasons are in [`open-questions.md`](open-questions.md), section "Infrastructure (step 3)", bullets that start with "persistence".

### Files

| React Native (`src/infrastructure/persistence/`) | Dart (under `lib/`) | Note |
| --- | --- | --- |
| `schema.ts` | `features/{meetings,documents,votes}/infrastructure/persistence/schema.dart` | `TABLE`, `COLUMN`, `INDEX` are split by feature: `MeetingStoredTable` and `MeetingStoredColumn`, `DocumentStoredTable`, `DocumentStoredColumn` and `DocumentStoredIndex`, `VoteStoredTable`, `VoteStoredColumn` and `VoteStoredIndex`; `OUTBOX_QUARANTINED` is `outboxQuarantined` (votes) |
| (the SQL of the queries) | `features/{meetings,documents,votes}/infrastructure/persistence/tables.dart` | The tables each feature owns, as drift knows them, for the queries that write; the file is made by the migrations |
| `SqlDatabase.ts` | `app/persistence/boardroom_database.dart` | `BoardroomDatabase`: the drift database replaces `createSqlDatabase` (serial statements, transactions); it lists the tables of the features |
| `migrations.ts` | `app/persistence/migrations.dart`, `core/infrastructure/persistence/migrate.dart` | `migrations` (the history of the file, which reads the names of the features) is the app's; the class `Migration` is the machinery's, in the core; the SQL is the same text |
| `migrate.ts` | `core/infrastructure/persistence/migrate.dart` | `migrationStrategyOf` (drift runs it when it opens the file), `MigrationFailure`, `migrationsAreInOrder`; there is no `runMigrations` nor outcome |
| `DatabaseOpener.ts` | `core/infrastructure/persistence/database_opener.dart` | `DatabaseOpener`, `EngineConnection` (`exec`, `all`, `close`, `toExecutor`), `connectionPragmas` |
| `ExpoSqliteOpener.ts` | `core/infrastructure/persistence/sqlite3_opener.dart` | `Sqlite3Opener` over `sqlite3` (SQLite3MultipleCiphers), `createDeviceDatabaseOpener` |
| `ExpoRandomBytes.ts`, `randomKey.ts` | `core/infrastructure/persistence/random_key.dart` | `RandomBytes`, `keyFromBytes`, `secureRandomBytes` (`Random.secure`) |
| `databaseKey.ts` | `core/infrastructure/persistence/database_key.dart` | `KeyState`, `formatKeyState`, `parseKeyState`, `databaseFileName` |
| `unlockDatabase.ts` | `core/infrastructure/persistence/unlock_database.dart` | `UnlockFailure`, `unlockDatabase` |
| `localDataReset.ts` | `core/infrastructure/persistence/local_data_reset.dart` | `ResetReason`, `markLocalDataReset`, `hasLocalDataReset`, `clearLocalDataReset`, `readLocalDataResetNotice` |
| `protectedDatabase.ts` | `core/infrastructure/persistence/protected_database.dart` | `openProtectedDatabase`, `ProtectedDatabaseOptions`, `DatabaseUnavailable`, `DatabaseFailureReason`; it answers a `BoardroomDatabase` |
| `guarded.ts` | `core/infrastructure/persistence/guarded.dart` | `guardedRead`, `guardedWrite`, plus `attemptOnDatabase` and `engineFailureOf` (drift wraps some failures) |
| `storedMeeting.ts` | `features/meetings/infrastructure/stored_meeting.dart` | `json_serializable` (checked mode) |
| `storedDocument.ts` | `features/documents/infrastructure/stored_document.dart` | `json_serializable` (checked mode) |
| (inside `SqliteMeetingCache.ts` and `SqliteDocumentCache.ts`) | `core/infrastructure/persistence/stored_payload.dart` | `decodePayload`, `Unreadable`, `instantOf`: the read of a payload both caches share |
| `SqliteMeetingCache.ts` | `features/meetings/infrastructure/drift_meeting_cache.dart` | `DriftMeetingCache` |
| `SqliteDocumentCache.ts` | `features/documents/infrastructure/drift_document_cache.dart` | `DriftDocumentCache`, `DriftDocumentCacheOptions`; `sweepOrphans` answers the failure, the composition root reports it once as `orphanFileNotDeleted` |
| `SqliteVoteOutbox.ts` | `features/votes/infrastructure/drift_vote_outbox.dart` | `DriftVoteOutbox` |

### Test support

| React Native (`src/infrastructure/testing/`) | Dart (`test/support/infrastructure/`) | Note |
| --- | --- | --- |
| `testDatabase.ts` | `test_database.dart` | `openTestDatabase` (in memory, or a file of a directory), `openTestFile`, `TestDatabase.reopen`, and raw statements on `BoardroomDatabase` (`run`, `all`) |
| `FaultyConnection.ts` | `database_faults.dart` | A drift `QueryInterceptor`: `failNext`, `failWhileAddingData`, `hang`, plus `failWhileMatching` and `failNextRollback` |
| `SimulatedCipherOpener.ts` | `watched_opener.dart` | No simulation: the files are encrypted for real by SQLite3MultipleCiphers. The wrapper records the keys used, the files removed and the connections opened and closed, and can corrupt a file for real, take the cipher away, fail or hang an open or a statement |
| `NodeSqlite.ts` (`NodeSqliteOpener`, `NodeSqliteConnection`) | `Sqlite3Opener` itself | The engine of the tests is the engine of the device |
| `NodeSqlite.ts` (`temporaryDirectory`, `freshDirectory`) | `test_files.dart` | Already there (foundations) |
| `nodeRandomBytes.ts` | `secureRandomBytes` | The generator of the device is the one of the tests |
| `fakeExpoSqlite.ts` | (none) | Expo-specific |
| `documentDevice.ts` | `document_device.dart` | `aDocumentDevice` takes an optional `around`, to put a volume between the faulty one and the disk |
| (a rejection with `code: 'EBUSY'` in the tests) | `locked_file_volume.dart` | A volume where some files cannot be deleted (`os error 16`) |

### Tests

"RN" is the number of tests of the React Native file once its `each` tables and its contract suites are expanded, "Dart" the number of tests of the Dart file (the contract suites of the Drift adapters run three times, see below). Every RN test that is not listed under "Not ported" has a Dart test with the same full name, with the class names above (`Sqlite…` is `Drift…`, `createSqlDatabase` is `BoardroomDatabase`, `ExpoSqliteOpener` is `Sqlite3Opener`).

| React Native test file | Dart test file (under `test/`) | RN | Dart | Not ported (RN scenario: reason) |
| --- | --- | --- | --- | --- |
| `databaseKey.test.ts` | `core/infrastructure/persistence/database_key_test.dart` | 18 | 20 | |
| `localDataReset.test.ts` | `core/infrastructure/persistence/local_data_reset_test.dart` | 8 | 9 | |
| `migrate.test.ts` | `core/infrastructure/persistence/migrate_test.dart` | 20 | 19 | `... do nothing for an empty list, and leave the database at version 0`: drift has no database without a version, an empty list is refused (the Dart test `... refuse an empty list of migrations: drift has no database without a version` says so); `... refuse a version that is not whole in the list of migrations, before touching the database`: a version is an `int`; `... report a version that cannot be read, without throwing`: drift reads the version while it opens the file, there is no separate read to fail |
| `unlockDatabase.test.ts` | `core/infrastructure/persistence/unlock_database_test.dart` | 18 | 18 | `... says it failed, not that the key is rejected, for nothing`: a Dart failure cannot be `null` |
| `protectedDatabase.test.ts` | `core/infrastructure/persistence/protected_database_test.dart` | 63 | 68 | `... when it answers something that is not bytes` and `... when it answers an array of numbers`: `RandomBytes` answers a `Uint8List`, the type system refuses the rest |
| `SqliteMeetingCache.test.ts` | `features/meetings/infrastructure/drift_meeting_cache_test.dart` | 50 | 116 | `... keeps no reference to the objects that go in or out hands out a new object at every read`: not in the Dart contract suite (`docs/parity/exceptions.md`) |
| `SqliteDocumentCache.test.ts` | `features/documents/infrastructure/drift_document_cache_test.dart` | 58 | 118 | The two `... keeps no reference ...` scenarios of the contract suite (`docs/parity/exceptions.md`) |
| `SqliteVoteOutbox.test.ts` | `features/votes/infrastructure/drift_vote_outbox_test.dart` | 96 | 196 | The three `... keeps no reference ...` scenarios of the contract suite (`docs/parity/exceptions.md`) |
| `SqlDatabase.test.ts` | `app/persistence/boardroom_database_test.dart` | 11 | 12 | `... refuses a statement sent through the transaction once it has ended`: the transaction of drift is the zone of the call, there is no object to keep |
| `ExpoSqliteOpener.test.ts` | `core/infrastructure/persistence/sqlite3_opener_test.dart` | 7 | 11 | `... runs a statement that takes no parameter and answers nothing, as it is` and `... removing a database lets any other failure go: a database that is open cannot be deleted`: Expo-specific (they check what a stand-in for the native module received, and that module's refusal to delete an open file). `... gives a connection that runs statements with their parameters and reads rows` is `... gives a connection that runs statements and reads rows`: the connection takes no parameter |

349 React Native tests, 334 with a Dart test of the same name (the renamed one of `ExpoSqliteOpener` counted), 15 not ported (the reasons above).

The contract suites of `MeetingCache`, `DocumentCache` and `VoteOutbox` run against each Drift adapter three times: on a plain file (every group, `reopen` included), on a database in memory (the groups that need the file to be opened again are shown as skipped, 12 tests), and on the database the app opens, encrypted for real with a key kept in a keychain in memory (`openProtectedDatabase`, every group, none skipped). The second and third runs are named `DriftMeetingCache in memory …`, `DriftDocumentCache in memory …`, `DriftVoteOutbox in memory …` and `DriftMeetingCache encrypted …`, `DriftDocumentCache encrypted …`, `DriftVoteOutbox encrypted …`; their tests are listed below as Dart-only.

### Dart tests with no React Native scenario

| Dart test file (under `test/`) | Tests | What |
| --- | --- | --- |
| `core/infrastructure/persistence/database_key_test.dart` | 2 | The state never prints its key; it compares by generation and key |
| `core/infrastructure/persistence/local_data_reset_test.dart` | 1 | The default time limit of the notice |
| `core/infrastructure/persistence/migrate_test.dart` | 2 | An empty list is refused; `MigrationFailure` compares by value and prints no statement |
| `core/infrastructure/persistence/unlock_database_test.dart` | 1 | A file of the engine of the device is read back with the key it was written with |
| `core/infrastructure/persistence/protected_database_test.dart` | 7 | An unlock that never answers, a connection that cannot be set up (with and without a close that fails), a list of migrations that is not 1, 2, 3, ... (before the file is touched), the error and the options (`copyWith`) |
| `features/meetings/infrastructure/drift_meeting_cache_test.dart` | 67 | The pages of the two periods are kept apart; the contract suite on a database in memory (33) and on the encrypted database (33) |
| `features/documents/infrastructure/drift_document_cache_test.dart` | 62 | A row whose location is no location is removed by a purge and is not a file the sweep keeps; the contract suite on a database in memory (30) and on the encrypted database (30) |
| `features/votes/infrastructure/drift_vote_outbox_test.dart` | 103 | The contract suite on a database in memory (51) and on the encrypted database (51); the votes are written in a file that is no SQLite database to whoever has not the key |
| `app/persistence/boardroom_database_test.dart` | 2 | A database in memory keeps nothing after it is closed; a closed database fails every statement |
| `core/infrastructure/persistence/sqlite3_opener_test.dart` | 6 | The folder is made at the first open; the rows do not change afterwards; closing twice; drift takes the connection over and closes it; only the main file is removed; the opener of the device keeps its files in a folder of the private storage |
| `core/infrastructure/persistence/guarded_test.dart` | 15 | `guardedRead`, `guardedWrite`, `engineFailureOf` (the failure under the wrapper drift puts on it, a rollback that fails after the work failed) (no test file in React Native) |
| `core/infrastructure/persistence/random_key_test.dart` | 11 | `keyFromBytes` and `secureRandomBytes` on their own (React Native tests them through `openProtectedDatabase` only) |
| `core/infrastructure/persistence/stored_payload_test.dart` | 8 | `decodePayload`, `instantOf`, `Unreadable` (inside the caches in React Native) |
| `app/persistence/tables_test.dart` | 4 | The tables of drift are the tables the migrations create, with the names of the `schema.dart` of the features, the same columns, types and nullability (no counterpart: the queries are text in React Native) |

The persistence folder has 625 Dart tests in the files above, besides `core/infrastructure/persistence/encrypted_sqlite_test.dart` (foundations, 8 tests, listed in the first table of Dart-only tests); `flutter test test/core/infrastructure/persistence test/features/*/infrastructure test/app/persistence` runs them all.

## Screen protection plugin (step 4)

The local plugin `packages/screen_protection` (Pigeon, Kotlin, Swift: [`../native-module.md`](../native-module.md)) and its adapter. It replaces the local Expo module `modules/screen-protection` of React Native and the folder `src/features/documents/infrastructure/native`. The native code has no React Native test (it is checked on a device); the Dart side of the plugin and the Kotlin and Swift logic that can run without a device have tests of their own, listed below.

### Files

| React Native | Dart (under `lib/` unless it says `packages/`) | Note |
| --- | --- | --- |
| `native/NativeScreenProtection.ts` | `features/documents/infrastructure/native/native_screen_protection.dart` | `NativeScreenProtection`, over `ScreenProtectionModuleApi`. `DEFAULT_NATIVE_TIMEOUT_MILLIS` is `defaultNativeTimeoutMillis`. The module is `null` where the platform has no plugin (`undefined` in React Native). The two events of the module (`onScreenshotTaken`, `onCaptureChanged`) are one stream of typed messages (`CaptureEventMessage`, sealed), so there is one native listener, not two |
| `native/ScreenProtectionModuleApi.ts` | `features/documents/infrastructure/native/screen_protection_module_api.dart` | The seam: `setProtectionEnabled`, `isCaptured`, `addListener` (with an `onError` for the stream, which an Expo event has not). `NATIVE_EVENT` and `NativeSubscription` have no counterpart: the stream is typed, and the subscription is a function (`Unsubscribe`) |
| `native/loadScreenProtectionModule.ts` | `features/documents/infrastructure/native/pigeon_screen_protection_module.dart` | `PigeonScreenProtectionModule` (the module over the typed channel Pigeon generates) and `loadScreenProtectionModule` (null on a platform that is not Android or iOS, where React Native tests whether the module loaded) |
| `modules/screen-protection/index.ts`, `src/ScreenProtectionModule.ts`, `src/ScreenProtection.types.ts` | `packages/screen_protection/lib/screen_protection.dart`, `lib/src/messages.g.dart` (generated), `pigeons/screen_protection_api.dart` | The calls and the events, declared once and generated for Dart, Kotlin and Swift. `CaptureChangedEvent` is `CaptureChangedMessage`; the screenshot event, which has no payload, is `ScreenshotTakenMessage`; `SecureLayerFallbackEvent` is `SecureLayerFallbackMessage`. `capabilities()` is new (what the platform can do) |
| `modules/screen-protection/src/ScreenProtectionSecureView.tsx` | `packages/screen_protection/lib/src/secure_view.dart`, `lib/screen_protection_view.dart` | `SecureView` |
| `features/documents/presentation/components/SecureContent.tsx` | `features/documents/presentation/secure_content.dart` | The one file of the presentation allowed to import the plugin, and only its widget entry point: `presentationExemptions` in `tool/check_imports.dart`, tested in `test/tool/check_imports_test.dart` (the counterpart of the lint rule of React Native) |
| `modules/screen-protection/ios/ScreenProtectionModule.swift`, `ScreenProtectionSecureView.swift` | `packages/screen_protection/ios/screen_protection/Sources/screen_protection/` | The app switcher cover, the screenshot and recording detection, the secure view. The selection of a `PDFView` is not ported: it belongs to the PDF viewer, which is not chosen yet ([`../native-module.md`](../native-module.md)) |
| `modules/screen-protection/android/.../*.kt` | `packages/screen_protection/android/src/main/kotlin/com/boardroom/screenprotection/` | `FLAG_SECURE`, `ScreenshotDetector`, `RecordingDetector`; the manifest declares the same two permissions |
| `features/documents/infrastructure/testing/FakeScreenProtectionModule.ts` | `test/support/infrastructure/fake_screen_protection_module.dart` | The stand-in of the native side. `listenerCount` is the number of listeners of the one stream; `captured`, `failure`, `throwsSynchronously`, `hanging`, `captureFailure`, `addFailure`, `removeFailure` are the switches of the React Native fake |
| (the demo screen: none) | `features/documents/presentation/screen_protection_demo_screen.dart` | New in Flutter: a screen to try the plugin on a device, reached from the placeholder home screen until the router |

### Tests

| React Native test file | Dart test file (under `test/`) | RN | Dart | Not ported (RN scenario: reason) |
| --- | --- | --- | --- | --- |
| `native/NativeScreenProtection.test.ts` | `features/documents/infrastructure/native/native_screen_protection_test.dart` | 36 | 36 | `NativeScreenProtection, the events ignores a report that is not a state`: the events are typed (`CaptureEventMessage`), a payload that is not a state cannot be written. One Dart test takes its place: `... when something goes wrong says so when the stream of events fails, and the events that follow still come`. In `... does not throw when the module cannot be listened to, and says so` the monitoring hears one failure, not two, as there is one listener. Same names otherwise (35), the contract suite included (9) |

The suite `describeScreenProtectionContract` runs against `NativeScreenProtection` over `FakeScreenProtectionModule`, whose `setProtectionEnabled` turns the protection on later than it turns it off, so the order of the calls is really tested (as the React Native fake does).

### Dart tests with no React Native scenario

| Test file | Tests | What |
| --- | --- | --- |
| `test/features/documents/infrastructure/native/pigeon_screen_protection_module_test.dart` | 8 | The module over a fake of the generated host API: the calls reach it, its failure reaches the adapter, the events of the stream reach the listener from one stream made once, a failure of the stream reaches `onError`, and `loadScreenProtectionModule` by platform |
| `test/features/documents/presentation/screen_protection_demo_screen_test.dart` | 8 | The demo screen over a fake port: the switch, the errors (unsupported, failed), the list of captures, the French texts, and that leaving the screen turns the protection off |
| `test/app/app_test.dart` | 1 | The home screen opens the demo screen |
| `test/tool/check_imports_test.dart` | 4 | The exemption of `SecureContent`: one file, one URI, nothing else |
| `packages/screen_protection/test/screen_protection_api_test.dart` | 6 | The plugin's Dart side over a mocked channel: the calls, a native error as `PlatformException`, `capabilities`, the typed events, equality |
| `packages/screen_protection/test/secure_view_test.dart` | 7 | `SecureView`: the child alone on Android and elsewhere, the native view on iOS only while secure, mounted and removed as `secure` changes, the fallback reason, and that it stops listening when it is not secure |
| `packages/screen_protection/android/src/test/kotlin/...` | 9 | `ProtectionState` (the flag is applied to the window of each activity, remembered without one), `CaptureStateTracker` (a state is told once), `Capabilities` (by API level); JVM, `./gradlew :screen_protection:testDebugUnitTest` |
| `packages/screen_protection/ios/screen_protection/Tests/` | 6 | `CaptureDecision` (what the scenes and the screens say about a capture) and `CaptureMask` (the private mask value); XCTest, run on a simulator by the owner (the logic itself was run on macOS in a scratch package) |

## Contract suites: port, adapters, run

The contract suites of `test/support/contracts` are written once and run against every adapter of their port, as in React Native (`fakes.contracts.test.ts` for the fakes, one test file per adapter for the others). A suite that runs against an adapter is called with the name of the adapter, so its tests are named `<Adapter> honours the <Port> contract …`. "Tests" is the number of tests the suite has for that adapter, "skipped" the ones its options switch off (a store in memory cannot fail a statement nor be reopened).

| Port | Adapter | Run in | Tests | Skipped |
| --- | --- | --- | --- | --- |
| `AuthSession` | `HttpAuthSession` | `test/app/http/http_repositories_test.dart` | 12 | 0 |
|  | `InMemoryAuthSession` | `test/app/dev/in_memory/in_memory_auth_session_test.dart` | 12 | 0 |
| `MeetingRepository` | `HttpMeetingRepository` | `test/app/http/http_repositories_test.dart` | 24 | 0 |
|  | `InMemoryMeetingRepository` | `test/app/dev/in_memory/in_memory_repositories_test.dart` | 24 | 0 |
| `DocumentRepository` | `HttpDocumentRepository` | `test/app/http/http_repositories_test.dart` | 11 | 0 |
|  | `InMemoryDocumentRepository` | `test/app/dev/in_memory/in_memory_repositories_test.dart` | 11 | 0 |
| `VoteRepository` | `HttpVoteRepository` | `test/app/http/http_repositories_test.dart` | 19 | 0 |
|  | `InMemoryVoteRepository` | `test/app/dev/in_memory/in_memory_repositories_test.dart` | 19 | 0 |
| `MeetingCache` | `DriftMeetingCache` (a file) | `test/features/meetings/infrastructure/drift_meeting_cache_test.dart` | 33 | 0 |
|  | `DriftMeetingCache in memory` | `test/features/meetings/infrastructure/drift_meeting_cache_test.dart` | 33 | 3 |
|  | `DriftMeetingCache encrypted` | `test/features/meetings/infrastructure/drift_meeting_cache_test.dart` | 33 | 0 |
|  | `InMemoryMeetingCache` | `test/features/meetings/infrastructure/in_memory_meeting_cache_test.dart` | 33 | 8 |
| `DocumentCache` | `DriftDocumentCache` (a file) | `test/features/documents/infrastructure/drift_document_cache_test.dart` | 30 | 0 |
|  | `DriftDocumentCache in memory` | `test/features/documents/infrastructure/drift_document_cache_test.dart` | 30 | 3 |
|  | `DriftDocumentCache encrypted` | `test/features/documents/infrastructure/drift_document_cache_test.dart` | 30 | 0 |
|  | `InMemoryDocumentCache` | `test/features/documents/infrastructure/in_memory_document_cache_test.dart` | 30 | 8 |
| `VoteOutbox` | `DriftVoteOutbox` (a file) | `test/features/votes/infrastructure/drift_vote_outbox_test.dart` | 51 | 0 |
|  | `DriftVoteOutbox in memory` | `test/features/votes/infrastructure/drift_vote_outbox_test.dart` | 51 | 6 |
|  | `DriftVoteOutbox encrypted` | `test/features/votes/infrastructure/drift_vote_outbox_test.dart` | 51 | 0 |
|  | `InMemoryVoteOutbox` | `test/features/votes/infrastructure/in_memory_vote_outbox_test.dart` | 51 | 24 |
| `Connectivity` | `DeviceConnectivity` | `test/core/infrastructure/connectivity/device_connectivity_test.dart` | 10 | 0 |
|  | `SimulatedConnectivity` | `test/app/dev/in_memory/simulated_connectivity_test.dart` | 10 | 0 |
| `ScreenProtection` | `InMemoryScreenProtection` | `test/features/documents/infrastructure/in_memory_screen_protection_test.dart` | 9 | 0 |
|  | `NativeScreenProtection` | `test/features/documents/infrastructure/native/native_screen_protection_test.dart` | 9 | 0 |

The fakes of `test/support/fakes` run the same nine suites in `test/support/fakes/fakes_contracts_test.dart`, so a contract is checked against the fake and against every real adapter. Three ports have no contract suite, in React Native either, and their adapters have their own test files: `BiometricGate` (`DeviceBiometricGate`, `InMemoryBiometricGate`), `Monitoring` (`ConsoleMonitoring`, `SentryMonitoring`) and `Clock` (`SystemClock`). The drift adapters run each suite three times: on a plain file, where the groups that reopen the database run; in memory, where the key cannot be set (see [`open-questions.md`](open-questions.md), "persistence"); and on the encrypted database that `openProtectedDatabase` gives, which is the one of the app. The skipped tests of the adapters in memory come from the options their test file passes to the suite (no failing statement, no reopening, no unreadable entry), the same flags React Native passes as `IN_MEMORY_STORE`.

The dev-mode adapter of the brief is not a port of its own: the three repositories and the session of `Http…` run against `FixtureServer.adapter` (the dio `HttpClientAdapter` in front of `MockApi`) in these same contract runs, so they are checked on the fixtures; the routes themselves have their tests in `test/app/dev/fixture_server/` (`MockApi.test.ts` and the dio adapter).

## Totals of the step

React Native tests of `src/infrastructure` in scope, the ones that have a Dart test of the same full name (a class renamed as said in the tables counts as the same name), and the ones that are not ported (every reason is in the tables above). The four tables computed at run time of `fixtureTimeline.test.ts` count as one row each (6 rows, 250 Dart tests); `migrate.test.ts` counts its four expanded versions (20 rows). The names were compared mechanically, file by file, with `tool/ts_test_names.dart` on the React Native tests and `flutter test --machine` on the Dart ones.

| Part | RN tests | With a Dart test of the same name | Not ported |
| --- | --- | --- | --- |
| Foundations, fixture server, simulated server | 789 | 778 | 11 |
| Device and in-memory adapters | 298 | 288 | 10 |
| HTTP client and repositories | 313 | 309 | 4 |
| Persistence | 349 | 334 | 15 |
| **Step 3** | **1749** | **1709** | **40** |

The 40 are, by reason: 15 about values that are changed after they were handed over (3 `clonePlain`, and the 6 scenarios of the contract suites that `exceptions.md` lists, for each of the in-memory adapters and the Drift adapters: 12), because Dart values are immutable; 7 about JavaScript values that Dart typing cannot hold (3 of `describeFailure`, 4 truthiness tests of the biometric prompt); 2 page limits (`1.5`, `NaN`) that an `int` cannot be; 5 Expo-specific (3 `ExpoFileVolume`, 2 `ExpoSqliteOpener`); 4 for a platform that gives no stream (dio always gives one); 7 about what drift does by itself or a type that cannot be wrong (3 `migrate`, 2 `protectedDatabase`, 1 `unlockDatabase`, 1 `SqlDatabase`).

The infrastructure tests (the folder `test/infrastructure` before the move to the feature layout, now `test/core/infrastructure`, `test/features/*/infrastructure`, `test/app` and `test/support/infrastructure`) have 2424 Dart tests in 81 files, 52 of them skipped by the options of the contract suites above; `flutter test` runs 3902 tests with the domain, the application, the tooling and the fakes (110 skipped). The counter that `flutter test` prints (`+2423 ~52` and `+3843 ~110`) is higher: it also counts the `tearDownAll` hook of the 51 files that make a temporary directory. Line coverage of the infrastructure code (before the move, `lib/infrastructure`) is 96.3 % (the gate asks 70 % of the layers other than the domain and the application).
