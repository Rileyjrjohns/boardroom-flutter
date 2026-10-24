# Delivery

**Nothing is deployed from this repository.** The release pipeline is written, wired and tested, but it never uploads anything here: every step that signs or uploads is gated on the secrets of the stores, and this repository has none. Pushing a tag `v*` runs the CI and the check of the tag, writes in the summary of the run which platform is skipped and why, and stops: the two platform jobs are *skipped*, not failed (the same pattern as the `eas-update` job of the React Native repository, which is skipped without `EAS_PROJECT_ID`). What follows is what a real project would set to make it ship. The full description, with the diagram, is in [`docs/ci-cd.md`](ci-cd.md).

**Layout.** Fastlane is set up the way [the Flutter documentation](https://docs.flutter.dev/deployment/cd) recommends: one `fastlane/` folder per native project, [`ios/fastlane`](../ios/fastlane) and [`android/fastlane`](../android/fastlane), each with its `Fastfile` and its `Appfile`, so that each platform has its own lanes and its own environment. A single `Gemfile` at the root pins Fastlane to one exact version (`2.240.1`, locked in `Gemfile.lock`); Bundler finds it from the two folders. The Flutter project is built with `flutter build`, and Fastlane signs, uploads and fails early: it does not replace Flutter's build.

```sh
bundle config set --local path vendor/bundle && bundle install   # once
cd ios && bundle exec fastlane lanes                              # lists the lanes (the same in android/)
```

| Lane (`ios` and `android`) | What it does                                                                                                                                                                                       |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci_signing`               | iOS: imports the distribution certificate (p12) into a temporary keychain and installs the provisioning profile, then switches the Xcode project to manual signing with that profile. Android: writes the upload keystore and `android/key.properties`. Everything comes from environment variables. |
| `build`                    | Runs `ci_signing`, then the signed release build: `flutter build ipa` with an export options file (`build/ios/ipa/*.ipa`), or `flutter build appbundle` (`build/app/outputs/bundle/release/app-release.aab`). |
| `beta`                     | Uploads what `build` made: iOS to TestFlight with an App Store Connect API key (`upload_to_testflight`), Android to the internal track of Google Play with a service account (`upload_to_play_store`, as a draft). |

Every lane stops at once, naming them, if a variable it needs is missing or empty. `ci_signing` and `beta` refuse to run outside CI (`CI=true`, which GitHub Actions sets) unless `FORCE_DELIVERY=1` says the person means it, so a local run cannot upload by accident. The release build is told which adapters it uses (`BOARDROOM_ADAPTERS`, `dev` unless the variable says `http`, with `BOARDROOM_API_BASE_URL`), because a release build refuses to guess. The build number is the run number of the workflow (`BUILD_NUMBER`).

**Android signing.** `android/app/build.gradle.kts` reads the upload key from `android/key.properties` (`storePassword`, `keyPassword`, `keyAlias`, `storeFile`), as the Flutter documentation says. The file is ignored by Git and absent here, and then the release build falls back to the debug key, so `flutter build appbundle --release` still works on a developer's machine. A debug-signed bundle can never be uploaded: Google Play refuses it.

## Secrets and variables

A real project sets these in the repository settings (Settings, Secrets and variables, Actions). Encode a file in base64 with `base64 -i file`. None of them is in this repository, and a test checks that no team id, bundle identifier or key is written in the files.

| Name                                  | Kind     | Platform | What it is                                                                       |
| ------------------------------------- | -------- | -------- | -------------------------------------------------------------------------------- |
| `IOS_BUNDLE_ID`                       | variable | iOS      | The bundle identifier of the app, the one of the Xcode project                    |
| `APPLE_TEAM_ID`                       | secret   | iOS      | The 10 characters team id of the Apple Developer account                         |
| `IOS_CERTIFICATE_P12_BASE64`          | secret   | iOS      | The distribution certificate with its private key, exported as .p12, in base64   |
| `IOS_CERTIFICATE_PASSWORD`            | secret   | iOS      | The password of that .p12                                                        |
| `IOS_PROVISIONING_PROFILE_BASE64`     | secret   | iOS      | The App Store provisioning profile of the bundle identifier, in base64            |
| `APP_STORE_CONNECT_KEY_ID`            | secret   | iOS      | The id of the App Store Connect API key (upload only)                            |
| `APP_STORE_CONNECT_ISSUER_ID`         | secret   | iOS      | The issuer id of the App Store Connect API keys                                  |
| `APP_STORE_CONNECT_KEY_BASE64`        | secret   | iOS      | The .p8 file of that API key, in base64                                          |
| `ANDROID_PACKAGE_NAME`                | variable | Android  | The application id of the app, the one of `android/app/build.gradle.kts`         |
| `ANDROID_KEYSTORE_BASE64`             | secret   | Android  | The upload keystore (.jks), in base64                                            |
| `ANDROID_KEYSTORE_PASSWORD`           | secret   | Android  | The password of the keystore                                                     |
| `ANDROID_KEY_PASSWORD`                | secret   | Android  | The password of the key                                                          |
| `ANDROID_KEY_ALIAS`                   | secret   | Android  | The alias of the key in the keystore                                             |
| `PLAY_SERVICE_ACCOUNT_JSON_BASE64`    | secret   | Android  | The JSON key of a Google Play service account allowed to release, in base64      |
| `BOARDROOM_ADAPTERS`                  | variable | both     | Optional. `dev` (the default: the simulated server) or `http`                    |
| `BOARDROOM_API_BASE_URL`              | variable | both     | Optional. The address of the API, for `http`                                     |

A platform is released only when **all** of its own rows (the ones that are not optional) are set. The workflow tests their presence in the job `verify` and writes the names of the missing ones in the summary of the run.

## What happens on a tag in this repository

1. `git tag v1.0.0 && git push origin v1.0.0` (not done here) starts two workflows: `End-to-end` runs its Android flows, and `Release` starts (`CI` is not started by the tag, but `Release` calls it, job `ci`).
2. `Release`, job `ci`: runs the checks of `ci.yml` on the tag; if they fail, no platform job runs. Job `verify`: checks that the tag is the `version` of `pubspec.yaml` (without the build number), or that version and a suffix for a candidate (`v1.0.0-rc.1`); a tag that lies fails here, before anything else.
3. Same job: tests the presence of the variables and the secrets of each platform. This repository has none, so both outputs are `false`, and the summary of the run says `ios: skipped, nothing is built or uploaded. Missing: ...` and the same for Android.
4. Jobs `ios` and `android` need `verify` and `ci` and have `if: !failure() && !cancelled() && needs.verify.outputs.<platform> == 'true'`: both are skipped (the macOS runner is never started), the run is green, and nothing was signed, built or uploaded.

With the secrets of a platform set, the same tag instead runs, on that platform: `flutter pub get`, `build_runner`, `fastlane <platform> build`, `fastlane <platform> beta`, and keeps the IPA or the bundle as an artifact of the run. A run started by hand (`workflow_dispatch`) does the same without the check of the tag and without the CI. The choice of Fastlane here, where the React Native repository uses EAS, is [ADR 0006](adr/0006-fastlane-for-delivery.md).
