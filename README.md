[![CI](https://github.com/Rileyjrjohns/boardroom-flutter/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Rileyjrjohns/boardroom-flutter/actions/workflows/ci.yml)

# Boardroom (Flutter)

Board meetings, documents and votes: the Flutter port of Boardroom, built to show that a well-made hexagonal architecture lets the domain move from one framework to another.

Port of [Boardroom (React Native)](https://github.com/Rileyjrjohns/boardroom) with the same domain. Both apps follow the same specification, kept in [`docs/spec`](docs/spec).

Status: step 2 of 8, domain and application. The app still shows a placeholder screen; the domain and the use cases are being translated from the specification and the React Native code, and the adapters and the screens come in the next steps. How the code is translated, file by file and test by test, is written in [`docs/porting.md`](docs/porting.md).

## Requirements

- Flutter 3.47.4 (stable), which ships Dart 3.13.3. The version is pinned in `pubspec.yaml` (`environment.flutter`).
- Xcode for iOS, Android Studio (or the Android SDK) for Android.

## Getting started

```sh
flutter pub get      # installs the dependencies and generates the localization classes
dart run build_runner build   # generates the freezed classes of the domain
flutter gen-l10n     # regenerates the localization classes by hand (after editing an ARB file)
flutter run          # runs the app on a connected device or emulator
flutter test         # runs all the tests
dart test test/domain test/application   # runs the pure Dart tests, without Flutter
```

## Generated code

Generated files are never committed. They are rebuilt with:

| What                                   | Command                                                    | Output                          |
| -------------------------------------- | ---------------------------------------------------------- | ------------------------------- |
| Localization classes (`AppLocalizations`) | `flutter gen-l10n` (also run by `flutter pub get`)       | `lib/l10n/app_localizations*.dart` |
| Freezed and JSON code                  | `dart run build_runner build` | `*.freezed.dart`, `*.g.dart`    |

`flutter test` and `flutter analyze` do not regenerate the localization classes on their own: after a fresh clone, run `flutter pub get` first. The same goes for the freezed classes (the entities and value data of `lib/domain`): after a fresh clone, and after any change to a class annotated with `@freezed`, run `dart run build_runner build`, or `dart test` and `flutter analyze` fail on the missing `*.freezed.dart`. CI runs it before the analysis and the tests.
The texts live in `lib/l10n/app_en.arb` (English, the template and the fallback) and `lib/l10n/app_fr.arb` (French).

## Checks

[CI](.github/workflows/ci.yml) runs three jobs on every pull request and on every push to `main`. Run the same commands locally, from the root of the repository, after `flutter pub get` (and, for the last two jobs, `dart run build_runner build`).

**Import rules** (job `Import rules`): a file may only import what its layer allows (see [Layers](#layers)).

```sh
dart run tool/check_imports.dart
```

**Analyze, format, tests, coverage** (job `Analyze, format, tests, coverage`):

```sh
dart run build_runner build   # the freezed classes, needed by the analysis and the tests
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
dart test test/domain test/application test/tool   # pure Dart tests, no Flutter
dart run tool/coverage_helper.dart       # writes test/coverage_helper_test.dart (ignored by Git)
flutter test --coverage                  # all the tests, writes coverage/lcov.info
dart run tool/coverage_gate.dart         # prints the coverage table, fails under a threshold
```

The coverage gate is on lines, the only figure that `flutter test --coverage` reports. Generated files (`*.g.dart`, `*.freezed.dart` and the localization classes) are left out. The thresholds are the ones of the React Native repository:

| Scope                                                       | Threshold |
| ----------------------------------------------------------- | --------- |
| `lib/domain`                                                | 90 %      |
| `lib/application`                                           | 90 %      |
| everything else together (infrastructure, presentation, di) | 70 %      |

A layer with no code yet is not checked. `tool/coverage_helper.dart` imports every library of `lib/` in a generated test, so a file that no test loads counts as 0 % instead of being missing from the report. In CI the table is added to the summary of the run and `coverage/lcov.info` is uploaded as an artifact.

**Scenario parity with React Native** (job `Scenario parity with React Native`): the Flutter tests of the domain and of the application must be the tests of the React Native app, one for one, with the same names. The React Native repository is checked out at the commit written in [`docs/parity/RN_COMMIT`](docs/parity/RN_COMMIT).

```sh
git clone https://github.com/Rileyjrjohns/boardroom ../boardroom && git -C ../boardroom checkout "$(cat docs/parity/RN_COMMIT)"
dart run tool/scenario_parity.dart --rn ../boardroom                                   # every test file
dart run tool/scenario_parity.dart --rn ../boardroom --only src/domain/value-objects   # one folder
dart run tool/scenario_parity.dart --rn ../boardroom --only src/application/use-cases --table   # the parity table of the use cases
```

The script reads the test sources of `src/domain` and `src/application`, expands the `it.each` tables the way Jest does, runs `dart test --reporter json` to get the names of the Dart tests, and compares the full names file by file (the mapping of the paths, the formation of the names and the translation of the assertions are in [`docs/porting.md`](docs/porting.md)). It fails on a scenario with no Dart test and on a Dart test with no scenario, unless [`docs/parity/exceptions.md`](docs/parity/exceptions.md) (a scenario that cannot exist in Dart) or [`docs/parity/extras.md`](docs/parity/extras.md) (a Dart-only test) explains it. The points where the specification was ambiguous, or where Dart forced a choice, are in [`docs/parity/open-questions.md`](docs/parity/open-questions.md).

The lint rules are those of `very_good_analysis` with `strict-casts`, `strict-inference` and `strict-raw-types`.

## Layers

| Folder                | Role                                              | May import                          |
| --------------------- | ------------------------------------------------- | ----------------------------------- |
| `lib/domain`          | Business rules, pure Dart                         | itself                              |
| `lib/application`     | Use cases and ports, pure Dart                    | `domain`                            |
| `lib/infrastructure`  | Adapters (dio, drift, secure storage, local_auth) | `domain`, `application`             |
| `lib/presentation`    | Widgets, screens, Riverpod notifiers              | `domain`, `application`, `di`       |
| `lib/di`              | Providers that wire ports and adapters            | all layers except `presentation`   |

Each folder has a `README.md` with the details.

`presentation` and `di` also never import the packages behind the adapters (dio, drift, flutter_secure_storage, local_auth, screen_protection, sqlite3), and only the files that `flutter gen-l10n` writes are exempt in `lib/l10n`. `tool/check_imports.dart` enforces all of this.
