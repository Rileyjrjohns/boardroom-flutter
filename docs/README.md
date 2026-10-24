# Documentation

Start with the [README](../README.md): the pitch, the demo, the diagram of the ports and adapters, how to run the app, and how it corresponds to the React Native app. The documents below are the depth behind it.

| Document                                         | What it holds                                                                                                                                              |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [development.md](development.md)                 | Requirements, commands, generated code, the checks of the CI, the coverage gate, the golden tests and the Patrol flows                                    |
| [delivery.md](delivery.md)                       | The Fastlane lanes, the signing, the secrets and variables, and what a tag does in this repository                                                        |
| [architecture.md](architecture.md)               | The layout, the graph of the features, the layers, the inversions between features, and how `tool/check_imports.dart` enforces them                         |
| [presentation.md](presentation.md)               | The pattern of every screen: Riverpod providers and overrides, queries, actions, errors, test ids, texts, routes, and how to write a widget test            |
| [porting.md](porting.md)                         | How the React Native code is translated to Dart, file by file and test by test: names, branded values, errors, entities, tests, presentation               |
| [api.md](api.md)                                 | The HTTP contract between the app and a server, and what the fixture server adds                                                                           |
| [native-module.md](native-module.md)             | The local `screen_protection` plugin: what it does per platform, its limits, the typed channel, and what was verified                                      |
| [monitoring.md](monitoring.md)                   | The `Monitoring` port, `ConsoleMonitoring` in use, and how to turn on `SentryMonitoring`                                                                   |
| [ci-cd.md](ci-cd.md)                             | The three workflows, Fastlane, the secrets, and why nothing is deployed from this repository                                                               |
| [media/README.md](media/README.md)               | How the demo GIF and the screenshots of the README are captured from the app, and how to regenerate them                                                   |
| [parity/open-questions.md](parity/open-questions.md) | Every point where the specification was ambiguous, the two apps differ, or Dart forced a choice, with the decision                                      |
| [parity/exceptions.md](parity/exceptions.md)     | The React Native scenarios that cannot exist in Dart                                                                                                       |
| [parity/extras.md](parity/extras.md)             | The Dart tests that have no React Native scenario                                                                                                          |
| [parity/infrastructure.md](parity/infrastructure.md) | The adapters and the plugin, mapped to their React Native counterparts                                                                                 |
| [parity/presentation.md](parity/presentation.md) | The screens, mapped to their React Native counterparts                                                                                                     |
| [adr/](adr/README.md)                            | The architecture decision records, one short page each                                                                                                     |
| [spec/](spec/README.md)                          | The shared specification of the domain, the use cases, the ports and the screens, and the fixtures of the demo data (a verbatim copy, see `spec/SOURCE.md`) |

The links of these documents, and of the README, are checked by `test/tool/docs_links_test.dart`.
