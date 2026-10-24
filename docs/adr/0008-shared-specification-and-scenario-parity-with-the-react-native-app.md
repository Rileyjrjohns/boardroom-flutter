# 0008. A shared specification and scenario parity with the React Native app

- Status: Accepted
- Related: [0001](0001-feature-first-hexagonal-architecture-with-links-inverted-through-the-composition.md), [0007](0007-a-dio-fixture-server-as-the-dev-backend-and-the-http-mock.md)

## Context

The claim of this repository is that the domain moved to another framework unchanged. A claim like that decays: two code bases drift, and "same behaviour" becomes a feeling. It has to be something that fails when it stops being true.

## Decision

Two checks, one on the contract and one on the tests.

- **A shared specification, copied verbatim.** `docs/spec` is a copy of `docs/spec` of the React Native repository (domain, use cases, ports, screens, fixtures; the commit is in `docs/spec/SOURCE.md`). It is never edited here: a change is made in the React Native repository first and copied again. `test/tool/spec_conformance_test.dart` reads it as a specification and checks it against the Dart code: the enumerations and error codes, the use cases and the ports (found in the code, no more and no fewer), the routes and their names, and the demo data. The ports that Dart adds (the inversions of [0001](0001-feature-first-hexagonal-architecture-with-links-inverted-through-the-composition.md)) are listed in the test as Dart-only.
- **Scenario parity.** `tool/scenario_parity.dart --rn <checkout>` reads the test sources of the React Native repository statically (`it`, `describe`, `it.each` and the contract suites, expanded) and the Dart names from `dart test --reporter json`. It maps each React Native test file to a Dart file and fails on any scenario that has no Dart test of the same name, or the reverse, outside two lists of exceptions (`docs/parity/exceptions.md`). The last run: 85 files, 1146 React Native scenarios, 1216 Dart tests, 0 with differences. The 6 scenarios that cannot exist in Dart are in `docs/parity/exceptions.md` and the 76 Dart tests with no React Native scenario are in `docs/parity/extras.md`, each with its reason.
- **Pinned and run in CI.** `docs/parity/RN_COMMIT` pins the React Native commit; the job `Scenario parity with React Native` of `ci.yml` checks that repository out at that commit and runs the tool. `tool/ts_test_names.dart` has its own tests (`test/tool/scenario_parity_test.dart`).
- **Differences are written down.** Where Dart forces a change, [`docs/parity/open-questions.md`](../parity/open-questions.md) records the file, the choice and the reason, and [`docs/porting.md`](../porting.md) says how code and tests are translated.

## Consequences

- A behaviour changed in one app and not in the other is a red CI job, not a review remark. The parity covers `domain` and `application` and the glue (the pure folders), where the claim of portability lives; the adapters and the screens have different tests by nature (dio against a fixture server instead of MSW, widget tests instead of RNTL) and are mapped in `docs/parity/infrastructure.md` and `docs/parity/presentation.md`, not checked by name.
- The check is as strong as the names: a scenario with the same name and a weaker assertion passes. The translation rule (same assertions, in the language's idiom) is a review rule, backed by the exceptions list.
- Both repositories carry the cost of the contract: a change to the specification is two commits in two repositories.
- A few behaviours differ because the languages do: the lower-casing of an email differs on 467 code points between Dart and JavaScript, `trimText` follows JavaScript on U+0085, errors are `AppError` subclasses where TypeScript has unions, and 6 contract scenarios cannot be written on immutable values. All are decided and recorded, not silent.

## Alternatives considered

- **A review checklist.** Cheap, and it fails the first time someone is in a hurry.
- **Generate one code base from the other** (a transpiler, or a common IDL). The code of the two apps would then read like neither language, and the domain is small enough to translate by hand and prove by tests.
- **Share the tests as data** (JSON scenarios run by both). Stronger on the assertions, but it means rewriting the 1146 existing tests as data and giving up the idiomatic test of each framework. The name parity was the version that could be added without rewriting.
- **No specification, only the React Native code as the reference.** The port would copy its accidents. The specification is what lets a disagreement between the two be settled (and one was: `withVoteRecorded` on an unknown resolution corrected the specification, see the open questions).
