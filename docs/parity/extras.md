# Dart tests with no React Native scenario

A Dart test that the React Native tests have no scenario for, because it checks something that exists only in Dart. `tool/scenario_parity.dart` fails on any other Dart test that has no React Native counterpart, and on an entry that no longer matches a test.

One row per test: the Dart test file, the full name of the test (the descriptions of its `group`s and its own, joined with one space; a `|` is written `\|`), and a one-line reason. The name `*` stands for every test of a Dart file that has no React Native counterpart. See [../porting.md](../porting.md#7-tests).

| Dart test file | Full test name | Reason |
| -------------- | -------------- | ------ |
| `test/core/domain/shared/trim_text_test.dart` | `*` | `trimText` replaces `String.trim`, whose set of white space differs from the one of JavaScript; React Native has no test for `String.prototype.trim` |
| `test/app/composition/app_error_dart_test.dart` | `*` | The errors are Dart classes with their own equality, `code` and `payload`; the TypeScript ones are object literals. The tests pin each code and payload, the equality and the exhaustive `switch` over each sealed family. It is in the composition because it is the one place that sees every family |
| `test/core/domain/shared/result_dart_test.dart` | `*` | How a `Result` compares, prints and is matched exhaustively, which has no TypeScript counterpart |
| `test/features/auth/domain/value_objects/credentials_dart_test.dart` | `*` | The Dart `Credentials` can be printed; its password must not appear |
| `test/features/auth/domain/value_objects/email_address_dart_test.dart` | `*` | `toLowerCase` of Dart and of JavaScript follow different versions of Unicode; the test pins the letters a mailbox can have (ASCII, Latin, Greek without final sigma, Cyrillic) that both lower-case the same |
| `test/support/fakes/fakes_dart_test.dart` | `*` | `List.sort` of Dart is not stable, so `FakeMeetingRepository` breaks the ties itself (a stable sort, as JavaScript has); and `EnqueueResult.outcome` is a getter of the Dart union, where the TypeScript object carries `outcome` as a field |
| `test/core/application/ports/session_refusal_test.dart` | `*` | `SessionRefusal` is the plain answer of that port; React Native has no such type |
| `test/app/composition/retryable_codes_assembly_test.dart` | `*` | The retryable codes are declared by the core and by the documents, and assembled by the composition; React Native has one list in the application layer |
| `test/app/composition/session_data_purgers_test.dart` | `sessionDataPurgers cannot be changed once built` | The Dart list is unmodifiable, and a TypeScript array can be pushed to |
| `test/features/auth/application/session/auth_session_gate_test.dart` | `AuthSessionGate purgeSessionData captures a purge that fails and does not throw` | The Dart gate reports the failure itself to the monitoring, since the `SessionGate` port of core hides it from the caller; React Native has no such test for the guards it calls directly |
| `test/app/composition/settings_test.dart` | `*` | The counterpart of the React Native `src/composition/container/config.test.ts`, a test of the composition, which the scenario parity does not compare (it compares the domain and the application) |
| `test/app/composition/wire_use_cases_test.dart` | `*` | The counterpart of the React Native `src/composition/container/wireUseCases.test.ts`, a test of the composition, which the scenario parity does not compare (it compares the domain and the application) |
