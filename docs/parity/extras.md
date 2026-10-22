# Dart tests with no React Native scenario

A Dart test that the React Native tests have no scenario for, because it checks something that exists only in Dart. `tool/scenario_parity.dart` fails on any other Dart test that has no React Native counterpart, and on an entry that no longer matches a test.

One row per test: the Dart test file, the full name of the test (the descriptions of its `group`s and its own, joined with one space; a `|` is written `\|`), and a one-line reason. The name `*` stands for every test of a Dart file that has no React Native counterpart. See [../porting.md](../porting.md#7-tests).

| Dart test file | Full test name | Reason |
| -------------- | -------------- | ------ |
| `test/domain/shared/trim_text_test.dart` | `*` | `trimText` replaces `String.trim`, whose set of white space differs from the one of JavaScript; React Native has no test for `String.prototype.trim` |
| `test/domain/errors/app_error_dart_test.dart` | `*` | The errors are sealed Dart classes with their own equality, `code` and `payload`; the TypeScript ones are object literals. The tests pin each code and payload, the equality and the exhaustive `switch` |
| `test/domain/shared/result_dart_test.dart` | `*` | How a `Result` compares, prints and is matched exhaustively, which has no TypeScript counterpart |
| `test/domain/value_objects/credentials_dart_test.dart` | `*` | The Dart `Credentials` can be printed; its password must not appear |
| `test/domain/value_objects/email_address_dart_test.dart` | `*` | `toLowerCase` of Dart and of JavaScript follow different versions of Unicode; the test pins the letters a mailbox can have (ASCII, Latin, Greek without final sigma, Cyrillic) that both lower-case the same |
| `test/application/support/fakes_dart_test.dart` | `*` | `List.sort` of Dart is not stable, so `FakeMeetingRepository` breaks the ties itself (a stable sort, as JavaScript has); and `EnqueueResult.outcome` is a getter of the Dart union, where the TypeScript object carries `outcome` as a field |
