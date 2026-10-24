# Architecture decision records

An architecture decision record (ADR) is a short page that says what was decided, why, and what it costs. They are numbered, kept in the repository, and never rewritten once accepted: a changed decision is a new record that supersedes the old one. The format is the one of the [React Native twin](https://github.com/Rileyjrjohns/boardroom/tree/main/docs/adr): **Status**, **Context**, **Decision**, **Consequences**, **Alternatives considered**.

The numbering is this repository's own. It only records the decisions the Flutter port had to take again or take differently; the ones it shares with the React Native app (the `Result` type, i18n from the first screen, the security model, offline-first with an outbox) are the ones of the other app's records and are not repeated. Each record names the files where the decision can be seen. The [README](../../README.md) and the [architecture](../architecture.md) are where to see them at work.

| ADR                                                                                           | Title                                                                                  | Status   |
| --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | -------- |
| [0001](0001-feature-first-hexagonal-architecture-with-links-inverted-through-the-composition.md) | Feature-first hexagonal architecture, cross-feature links inverted through the composition | Accepted |
| [0002](0002-riverpod-rather-than-bloc.md)                                                     | Riverpod rather than Bloc for state and dependency injection                           | Accepted |
| [0003](0003-drift-rather-than-sqflite.md)                                                     | drift rather than sqflite, with SQLite3MultipleCiphers and modular generation          | Accepted |
| [0004](0004-pigeon-rather-than-a-raw-methodchannel.md)                                        | A Pigeon plugin rather than a raw MethodChannel for ScreenProtection                   | Accepted |
| [0005](0005-patrol-rather-than-integration-test-alone.md)                                     | Patrol rather than integration_test alone                                              | Accepted |
| [0006](0006-fastlane-for-delivery.md)                                                         | Fastlane for delivery, secrets-gated, nothing deployed                                 | Accepted |
| [0007](0007-a-dio-fixture-server-as-the-dev-backend-and-the-http-mock.md)                     | A dio fixture server as the development backend and the HTTP mock                      | Accepted |
| [0008](0008-shared-specification-and-scenario-parity-with-the-react-native-app.md)            | A shared specification and scenario parity with the React Native app                   | Accepted |

## Writing a new record

Copy the headings of any record, take the next number, and keep it to one page. State the context with the facts that force the decision, say what was decided in terms that can be checked in the repository, be honest about the consequences that hurt, and list the alternatives that were really considered, with the reason each lost. If a decision replaces an earlier one, set the status of the earlier record to "Superseded by NNNN" and say so in the new one.
