# 0001. Feature-first hexagonal architecture, cross-feature links inverted through the composition

- Status: Accepted
- Related: [0002](0002-riverpod-rather-than-bloc.md), [0008](0008-shared-specification-and-scenario-parity-with-the-react-native-app.md)

## Context

The point of this repository is to show that a hexagonal architecture lets the domain move from one framework to another. The React Native twin ([ADR 0015 there](https://github.com/Rileyjrjohns/boardroom/blob/main/docs/adr/0015-feature-first-hexagonal-architecture-with-links-inverted-through-the-composition.md)) is organised by feature, with a graph of dependencies between features that has no cycle. The port has to keep the same structure, or the comparison of the two apps means nothing.

The first layout of the port was by layer (`domain`, `application`, `infrastructure` at the top). It worked, but four modules reached across features: `purgeCaches` imported the two caches, the offline policy imported the session, `Meeting` imported the vote, and `recordVoteInCache` imported three features. In Dart a cycle between libraries is legal, so nothing would have stopped it from growing.

## Decision

- **Feature first, then by layer.** `lib/core` is the shared kernel, `lib/features/{auth,meetings,documents,votes}` are the features, `lib/app` is the composition. Each feature has `domain`, `application`, `infrastructure` and `presentation` folders ([architecture](../architecture.md)).
- **One graph, one direction.** `auth` depends on nothing, `meetings` on `auth`, `documents` and `votes` on both, everything on `core`. `core` imports no feature. A feature imports the `domain` and `application` of the features it depends on, never their `infrastructure`; its `presentation` may import their `presentation` (providers, components). Only `lib/app` and `lib/main.dart` import everything.
- **Where a feature needs something of one it may not import, it declares a port and the composition implements it.** The inversions are real code: `SessionGate` (declared in `core`, implemented by `auth`), `SessionDataPurger` (declared in `auth`, implemented by `meetings` and `documents`), `MeetingDocumentEvictor` (declared in `meetings`, implemented by `documents`) and `RecordedVoteSink` (declared in `votes`, implemented in `lib/app/composition/meeting_cache_vote_recorder.dart`). The retryable error codes follow the same idea: each package declares its own and `lib/app/composition/retryable_codes.dart` assembles the set of the specification.
- **The wiring is by Riverpod overrides** (see [0002](0002-riverpod-rather-than-bloc.md)): each feature's `presentation/providers.dart` declares providers that throw until `lib/app/providers/app_overrides.dart` gives them a value built by `lib/app/container`.
- **The rules are a build failure.** `tool/check_imports.dart` reads every import, export and part directive of `lib/` and `test/` with the Dart parser. It checks the layer rules, the `featureGraph` constant (and that the graph has no cycle), the allowed packages of `domain` and `application`, and that `presentation` imports no adapter package, with one exact exception (`secure_content.dart`, see [0004](0004-pigeon-rather-than-a-raw-methodchannel.md)). `test/tool/check_imports_test.dart` tests each rule both ways and runs the checker on the real tree. CI runs it as the job `Import rules`.

## Consequences

- The domain and the application are pure Dart (they run under `dart test`, without Flutter) and the tests prove the same scenarios as the React Native ones.
- A new dependency between two features is a reviewed edit of `featureGraph` with its reason; one that closes a cycle is refused and must be inverted with a port.
- Some code is longer than in the layered version: four extra ports, and the glue between features in `lib/app/composition`. That is the price of removing the edges, and each port is small.
- Dart has no union types and its error families have to be sealed in their own library, so the families of the features live in their features and `AppError` is an open base in `core` ([open questions](../parity/open-questions.md#deviations-from-the-react-native-structure-feature-first)). A `switch` over a family is exhaustive, one over `AppError` is not.
- The checker is a Dart script of the repository, not a package: it knows this layout only. That is on purpose, the same way the React Native twin configures `eslint-plugin-boundaries` for its layout.

## Alternatives considered

- **Keep the layers at the top** (`lib/domain`, `lib/application`...). The first layout. Simpler to browse, and it let four cross-feature imports grow; moving to features is what made them visible.
- **One Dart package per feature** (a pub workspace member each). The compiler would then refuse an undeclared dependency, but the workspace is used for the plugin only, a package per feature multiplies `pubspec.yaml` files for a demo, and it would not check the layers inside a feature, which the script does anyway.
- **`import_lint` or `dart_code_linter` rules.** Existing tools, but the graph, the cycle check and the exact exception of the presentation are specific; a script of about 1,000 lines with tests was clearer than the configuration of a plugin.
- **A `shared` feature that holds what features need from each other.** It removes the cycles by hiding them: a rule of a feature would sit in `shared`. A port keeps the rule with its owner.
