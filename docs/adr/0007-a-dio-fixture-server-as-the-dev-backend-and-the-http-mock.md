# 0007. A dio fixture server as the development backend and the HTTP mock

- Status: Accepted
- Related: [0001](0001-feature-first-hexagonal-architecture-with-links-inverted-through-the-composition.md), [0005](0005-patrol-rather-than-integration-test-alone.md), [0008](0008-shared-specification-and-scenario-parity-with-the-react-native-app.md)

## Context

The app must run with nothing to deploy: no server, no account, no network. The HTTP adapters also have to be tested against something that answers like the server of [`docs/api.md`](../api.md). The React Native app serves the two needs with two mechanisms ([ADR 0014 there](https://github.com/Rileyjrjohns/boardroom/blob/main/docs/adr/0014-in-memory-adapters-for-the-no-backend-demo.md)): its demo runs on in-memory adapters that never make an HTTP request, and MSW answers requests only in the tests of its HTTP adapters.

## Decision

One simulated server, reached through the real HTTP stack, for both the development build and the tests.

- **`MockApi`** (`lib/app/dev/fixture_server/mock_api.dart`) implements the routes of `docs/api.md` over the frozen fixtures of the specification (`docs/spec/fixtures`, listed as assets in `pubspec.yaml`): 24 upcoming and 42 past meetings and two accounts that share one password. Dates are shifted by the time elapsed since the `referenceDate` of the fixtures. It answers `503` while its simulated network is cut.
- **`FixtureServerAdapter`** is a dio `HttpClientAdapter` in front of it. It touches no network and listens on no port; it behaves like one (cancellation, timeouts, a 64 KiB limit on request bodies). The real HTTP adapters, the interceptor that attaches the token and the size limit run unchanged against it.
- **The `dev` configuration** (`--dart-define=BOARDROOM_ADAPTERS=dev`, the default of `flutter run`) builds the real HTTP repositories with a client whose adapter is the fixture server and the base address `https://api.boardroom.invalid` (a domain that cannot resolve, so a request that escaped would fail). Its caches, outbox and secure storage are in memory (`lib/app/dev/in_memory`, `lib/app/container/dev_ports.dart`), and the biometrics are simulated where none is enrolled.
- **The `http` configuration** builds the same repositories with a real dio client, the encrypted database ([0003](0003-drift-rather-than-sqflite.md)) and the keychain.
- **The tests** use `FixtureServer.create` for the HTTP adapters, so no interception library is needed.

## Consequences

- The development build exercises the HTTP client, the DTOs and the mappers; the React Native demo does not (its in-memory path skips them). The two apps differ here on purpose: Flutter shows the adapters against a server, React Native shows the architecture without them. The domain, the use cases and the ports are unchanged either way.
- There is one implementation of the server rules, and the tests and the demo agree on it. The persistence and the secure storage of the `http` configuration are not exercised by the default launch, as in React Native.
- The fixture server is a second implementation of a server beside the real one, so `docs/api.md` is the reference both must keep, and a change to the contract is a change to `MockApi`.
- Dio's adapter seam keeps it small (about 1,000 lines in `lib/app/dev/fixture_server`, most of them the routes). There is no HTTP server process, so a real device cannot call it from outside the app (React Native's `npm run mock:api` can).

## Alternatives considered

- **In-memory adapters only, as in React Native.** No HTTP code on the demo path, and the DTOs and mappers are then tested only in unit tests. Rejected because the adapters are part of what the port has to show, and the fixture server was cheap once the API contract existed.
- **A local HTTP server in the app** (`shelf` on `localhost`). Real sockets, but a port to pick, iOS local-network prompts and a second process lifecycle.
- **`http_mock_adapter` or `mocktail` on dio.** Per-test stubs, not a server with state: a vote recorded must then show in the next read, which needs the simulated server anyway.
- **A separate Node mock API.** One more runtime for a Dart reader to install.
