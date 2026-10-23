# core

The shared kernel: what every feature uses and no feature owns. It holds no business rule of a feature (a meeting, a vote, a session): those are in `features/`.

It has the same layers as a feature, with the same rules:

| Folder | What | May import |
| ------ | ---- | ---------- |
| `domain/` | `shared/` (`Result`, the stable constants, the validation helpers), `errors/` (`AppError` and its families, `part` files of one library), `value_objects/` (the ids, `Instant`, `DurationMillis`, `Page`, `PageCursor`, `PageRequest`), `policies/cache_age.dart` | its own files, pure Dart |
| `application/` | `ports/` (`Clock`, `Monitoring`, `Connectivity`, and `ports/types/` for `CacheEntry` and `Unsubscribe`), `offline/` (`loadWithCacheFallback`, `Loaded`, `CacheResource`), `use_cases/observe_connectivity.dart`, `retryable_codes.dart` | `domain`, its own files, pure Dart |
| `infrastructure/` | the adapters and the machinery that no feature owns, in the folders of the table below | `domain`, `application`, the packages it adapts |

- `domain` and `application` are pure Dart: they run under plain `dart test`, without Flutter. They may import `dart:core|async|collection|math|typed_data|convert` and the pure packages `meta`, `collection`, `freezed_annotation`, `json_annotation` (the allowlist lives in `tool/check_imports.dart`).
- `infrastructure` must not import a `presentation` folder nor `lib/app`. It returns `Result` values at its boundary: an adapter catches what its tool throws, and nothing crosses a port as an exception.
- Nothing in `core` is meant to import a feature. Some files still do for now (the offline policy reaches the session helpers of `auth`, `device/` the biometric adapters): they are moved or inverted in a later step.

Folders of `infrastructure/` (the mapping with the React Native app is in [`docs/parity/infrastructure.md`](../../docs/parity/infrastructure.md)):

| Folder | What |
| ------ | ---- |
| `shared/` | `attempt` (work that settles in bounded time), `serial_queue`, `subscribers`, `results`, `sha256`, `valid`, the paths of the flaws of a body and the rejections of a vote |
| `clock/` | `SystemClock`, `timerSleep` |
| `monitoring/` | `ConsoleMonitoring`, and `SentryMonitoring` (disabled, see [`docs/monitoring.md`](../../docs/monitoring.md)) |
| `http/` | The constants of the API (`protocol`), the client (`HttpClient` over dio: the token attached by an interceptor, the timeouts, the size limits, no redirect and nothing stored, no retry), the gateway errors, the checks of an answer, and `dto/wire.dart` (the instants and `decodeWire`); the wire classes of a resource and the adapters of the remote ports are in the feature |
| `persistence/` | The machinery of the encrypted local database: the opener (`DatabaseOpener`, `Sqlite3Opener`), the key (`database_key`, `random_key`), `unlockDatabase`, `localDataReset`, `openProtectedDatabase`, the guards (`guarded`), `migrate` and `stored_payload`. The database itself (`BoardroomDatabase`, its tables and its migrations) is in `lib/app/persistence` |
| `files/` | `FileStore` over a `FileVolume` (`dart:io`) |
| `secure_storage/` | `SecureStorage`, the keychain of the device, over `flutter_secure_storage` |
| `connectivity/` | `DeviceConnectivity` over `NetworkStateApi` (`ConnectivityPlusNetworkState` over `connectivity_plus`); the simulated one is in `lib/app/dev/in_memory` |
| `device/` | `DevicePlatform`, the seams the adapters are written against (database engine, secure storage, random bytes, biometric prompt, network state), and `createDevicePlatform`, the one of a phone |
