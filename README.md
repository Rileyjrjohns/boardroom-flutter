[![CI](https://github.com/Rileyjrjohns/boardroom-flutter/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Rileyjrjohns/boardroom-flutter/actions/workflows/ci.yml)

# Boardroom (Flutter)

Board meetings, documents and votes: the Flutter port of Boardroom, built to show that a well-made hexagonal architecture lets the domain move from one framework to another.

Port of [Boardroom (React Native)](https://github.com/Rileyjrjohns/boardroom) with the same domain. Both apps follow the same specification, kept in [`docs/spec`](docs/spec).

Status: step 1 of 8, scaffold. The app shows a placeholder screen; the domain, the use cases, the adapters and the screens come in the next steps.

## Requirements

- Flutter 3.47.4 (stable), which ships Dart 3.13.3. The version is pinned in `pubspec.yaml` (`environment.flutter`).
- Xcode for iOS, Android Studio (or the Android SDK) for Android.

## Getting started

```sh
flutter pub get      # installs the dependencies and generates the localization classes
flutter gen-l10n     # regenerates the localization classes by hand (after editing an ARB file)
flutter run          # runs the app on a connected device or emulator
flutter test         # runs the widget tests
dart test test/domain test/application   # runs the pure Dart tests, without Flutter (from step 2, when they exist)
```

## Generated code

Generated files are never committed. They are rebuilt with:

| What                                   | Command                                                    | Output                          |
| -------------------------------------- | ---------------------------------------------------------- | ------------------------------- |
| Localization classes (`AppLocalizations`) | `flutter gen-l10n` (also run by `flutter pub get`)       | `lib/l10n/app_localizations*.dart` |
| Freezed and JSON code (later steps)    | `dart run build_runner build --delete-conflicting-outputs` | `*.freezed.dart`, `*.g.dart`    |

`flutter test` and `flutter analyze` do not regenerate the localization classes on their own: after a fresh clone, run `flutter pub get` first.
The texts live in `lib/l10n/app_en.arb` (English, the template and the fallback) and `lib/l10n/app_fr.arb` (French).

## Checks

[CI](.github/workflows/ci.yml) runs two jobs on every pull request and on every push to `main`. Run the same commands locally, from the root of the repository, after `flutter pub get`.

**Import rules** (job `Import rules`): a file may only import what its layer allows (see [Layers](#layers)).

```sh
dart run tool/check_imports.dart
```

**Analyze, format, tests, coverage** (job `Analyze, format, tests, coverage`):

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
dart test test/tool                      # pure Dart tests, no Flutter (add test/domain and test/application once they hold tests)
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
