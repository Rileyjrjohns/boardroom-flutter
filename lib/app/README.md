# app

The composition: the one place that knows every feature and chooses an implementation for each port. It may import anything of `core` and `features`, and the packages behind the adapters.

- `app.dart` and `home_screen.dart`: the root widget, which takes the `ScreenProtection` adapter (`main.dart` builds the native one), and the placeholder home screen with the way to the demo screen of the screen protection (localized texts only, from the ARB files, never a literal). The routing, the providers and the screens that belong to no feature come here.
- `composition/`: the glue between features, pure Dart (the layer `composition` of `tool/check_imports.dart`, which the test fakes may import): `sessionDataPurgers` (the list that `purgeCaches` of `auth` runs when a session ends: the meetings, then the documents), `MeetingCacheVoteRecorder` (the `RecordedVoteSink` of the votes, over the meeting cache, `withVoteRecorded` and the session guard), and `retryableCodes` and `isRetryableCode` (the codes of the core and of the documents put together). The tests of the glue, which need every feature, are in `test/app/composition`.
- `persistence/`: the drift database of the whole file: `BoardroomDatabase`, which lists the tables the features own (the `tables.dart` and `schema.dart` of their `infrastructure/persistence` folders), and `migrations`, the history of the file, which reads the names of the features. The opening machinery (encryption, key, unlock, the migration strategy) is in `core/infrastructure/persistence`, and each cache or outbox that uses the database is in its feature.
- `device/`: `DevicePlatform`, the seams the adapters are written against (database engine, secure storage, random bytes, biometric prompt, network state), and `createDevicePlatform`, the one of a phone. It bundles adapters of `core` and of `auth`, so it is composition.
- `dev/`: the simulated world of the development build and of the tests, which spans every feature:

| Folder | What |
| ------ | ---- |
| `in_memory/` | The simulated server (`InMemoryBackend`, `SimulatedNetwork`) and its seed, made of the fixtures (`fixtures/`: the loader that shifts the dates by whole days, the bundled files), and the adapters of the mock configuration that read the simulated server: the session store, the biometric gate, the connectivity that follows the switch of the simulated network, and the three repositories. The caches, the outbox and the screen protection are in their feature |
| `fixture_server/` | The routes of `docs/api.md` over the simulated server (`MockApi`) and a dio `HttpClientAdapter` in front of them (`FixtureServerAdapter`): the real HTTP adapters run unchanged against the fixtures in the development build and in the tests. `FixtureServer.create` builds it all |
| `pdf/` | A small PDF writer for the demo documents |

- The mapping with the React Native app is in [`docs/parity/infrastructure.md`](../../docs/parity/infrastructure.md).
- The features depend on each other in one direction only: every feature on `core`, `meetings` on `auth`, `documents` and `votes` on `meetings`, and `app` on all of them. `tool/check_imports.dart` enforces the graph, and [`docs/architecture.md`](../../docs/architecture.md) tells how the ports that `app` wires keep it without cycle.
- Every user-facing text comes from the ARB files, never from a literal.
