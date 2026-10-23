# infrastructure

The adapters: the classes that implement the ports of `application` with a real tool (dio, drift, flutter_secure_storage, local_auth, the screen protection plugin) or with an in-memory mock.

- May import: `domain`, `application` (to implement its ports), the packages it adapts, and its own files.
- Must not import: `presentation` or `di`.
- Returns `Result` values at its boundary: an adapter catches what its tool throws, and nothing crosses a port as an exception.

Folders (the mapping with the React Native app is in [`docs/parity/infrastructure.md`](../../docs/parity/infrastructure.md)):

| Folder | What |
| ------ | ---- |
| `shared/` | `attempt` (work that settles in bounded time), `serial_queue`, `subscribers`, `results`, `sha256`, `valid`, the paths of the flaws of a body and the rejections of a vote |
| `clock/` | `SystemClock`, `timerSleep` |
| `monitoring/` | `ConsoleMonitoring`, and `SentryMonitoring` (disabled, see [`docs/monitoring.md`](../../docs/monitoring.md)) |
| `http/` | The constants of the API (`protocol`), the wire classes of the bodies (`dto/`, read with `json_serializable`), the client (`HttpClient` over dio: the token attached by an interceptor, the timeouts, the size limits, no redirect and nothing stored, no retry) and the adapters of the remote ports (`HttpAuthSession`, `HttpMeetingRepository`, `HttpDocumentRepository`, `HttpVoteRepository`) |
| `in_memory/` | The simulated server (`InMemoryBackend`, `SimulatedNetwork`) and its seed, made of the fixtures (`fixtures/`: the loader that shifts the dates by whole days), and the adapters of the mock configuration that need nothing native: the session store, the biometric gate, the two caches, the outbox, the screen protection and the three repositories |
| `fixture_server/` | The routes of `docs/api.md` over the simulated server (`MockApi`) and a dio `HttpClientAdapter` in front of them (`FixtureServerAdapter`): the real HTTP adapters run unchanged against the fixtures in the development build and in the tests. `FixtureServer.create` builds it all |
| `persistence/` | The local database: drift (`BoardroomDatabase`, the migrations), its encrypted opening (`openProtectedDatabase`, the key held by the secure storage, `localDataReset`), and the three adapters that use it (`DriftMeetingCache`, `DriftDocumentCache`, `DriftVoteOutbox`) |
| `files/` | `FileStore` over a `FileVolume` (`dart:io`) |
| `documents/` | The name and the location of the content of a document |
| `pdf/` | A small PDF writer for the demo documents |
| `secure_storage/` | `SecureStorage`, the keychain of the device, and `SessionVault` |
| `biometrics/` | `DeviceBiometricGate` over a platform layer (`LocalAuthenticationApi`), and `DeviceLocalAuthentication`, which is that layer over `local_auth`; the text of the prompt comes from outside |
| `connectivity/` | `DeviceConnectivity` over `NetworkStateApi` (`ConnectivityPlusNetworkState` over `connectivity_plus`), and `SimulatedConnectivity`, which follows the switch of the simulated network |
| `device/` | `DevicePlatform`, the seams the adapters are written against (database engine, secure storage, random bytes, biometric prompt, network state), and `createDevicePlatform`, the one of a phone |
