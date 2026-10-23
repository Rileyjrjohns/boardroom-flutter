# app

The composition: the one place that knows every feature and chooses an implementation for each port. It may import anything of `core` and `features`, and the packages behind the adapters.

- `app.dart` and `home_screen.dart`: the root widget and the placeholder home screen (localized texts only, from the ARB files, never a literal). The routing, the providers and the screens that belong to no feature come here.
- `persistence/`: the drift database of the whole file, shared by the features: `BoardroomDatabase`, `schema` (the names of the tables, columns and indexes), `tables` (the tables as drift knows them) and `migrations`. The opening machinery (encryption, key, unlock) is in `core/infrastructure/persistence`, and each cache or outbox that uses the database is in its feature.
- `dev/`: the simulated world of the development build and of the tests, which spans every feature:

| Folder | What |
| ------ | ---- |
| `in_memory/` | The simulated server (`InMemoryBackend`, `SimulatedNetwork`) and its seed, made of the fixtures (`fixtures/`: the loader that shifts the dates by whole days, the bundled files), and the adapters of the mock configuration that read the simulated server: the session store, the biometric gate, the connectivity that follows the switch of the simulated network, and the three repositories. The caches, the outbox and the screen protection are in their feature |
| `fixture_server/` | The routes of `docs/api.md` over the simulated server (`MockApi`) and a dio `HttpClientAdapter` in front of them (`FixtureServerAdapter`): the real HTTP adapters run unchanged against the fixtures in the development build and in the tests. `FixtureServer.create` builds it all |
| `pdf/` | A small PDF writer for the demo documents |

- The mapping with the React Native app is in [`docs/parity/infrastructure.md`](../../docs/parity/infrastructure.md).
- The features are meant to depend on each other in one direction only: every feature on `core`, `meetings` on `auth`, `documents` and `votes` on `meetings`, and `app` on all of them. This is the intended graph: `tool/check_imports.dart` enforces the layers for now, not the graph.
- Every user-facing text comes from the ARB files, never from a literal.
