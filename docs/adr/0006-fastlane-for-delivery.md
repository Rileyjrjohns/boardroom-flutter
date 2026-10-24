# 0006. Fastlane for delivery, secrets-gated, nothing deployed

- Status: Accepted
- Related: [0005](0005-patrol-rather-than-integration-test-alone.md)

## Context

A store build needs signing credentials, a build number that only goes up, and an upload to TestFlight and Google Play. The React Native app delivers with EAS ([ADR 0007 there](https://github.com/Rileyjrjohns/boardroom/blob/main/docs/adr/0007-eas-as-the-default-delivery-pipeline.md)), which is a hosted service for Expo projects. A Flutter project has no equivalent from its framework, and Flutter's own documentation (docs.flutter.dev/deployment/cd) recommends Fastlane in a CI job. This repository has no store account, so the pipeline has to be complete and testable without ever uploading.

## Decision

Fastlane, driven by GitHub Actions, with every step that signs or uploads gated on secrets that this repository does not have ([CI/CD](../ci-cd.md)).

- **Layout.** One `fastlane/` folder per native project, `ios/fastlane` and `android/fastlane`, each with a `Fastfile` and an `Appfile`, as the Flutter documentation shows. One `Gemfile` at the root pins Fastlane to an exact version (2.240.1, locked in `Gemfile.lock`).
- **Lanes** (the same names on both platforms): `ci_signing` (iOS: a temporary keychain with the distribution certificate and the provisioning profile, then manual signing; Android: the upload keystore and `android/key.properties`), `build` (`flutter build ipa` or `flutter build appbundle`), `beta` (TestFlight with an App Store Connect API key, or the internal track of Google Play as a draft).
- **Explicit signing, not `match`.** `match` needs a private repository for the certificates, which is one more secret store; the explicit way is enough for one app and uses the secrets already there.
- **Safe by construction.** Every lane stops first, naming each missing variable. `ci_signing` and `beta` refuse to run outside CI unless `FORCE_DELIVERY=1`. No team id, bundle identifier, password or key is written in the repository.
- **The workflow** (`.github/workflows/release.yml`): a tag `v*` calls `ci.yml`, a `verify` job checks the tag against the `version` of `pubspec.yaml` and turns the presence of each platform's secrets into two outputs, and the `ios` and `android` jobs run only when their outputs are `true`. Without secrets they are skipped, not failed, no macOS runner starts, and the summary of the run says what is missing.
- **Checked by a test.** `test/tool/release_test.dart` verifies the workflows, the Fastfiles and the Gradle signing against each other (pinned actions, read-only permissions, named runners, the upload appearing once per platform, no hard-coded identity).

## Consequences

- Nothing is deployed from this repository, and a reader can see why: the run of a tag is green with both platform jobs skipped.
- Fastlane is a Ruby toolchain beside a Dart project, and signing material lives in the secrets of the repository, not in a hosted service. That is the trade the React Native ADR names as the reason to keep Fastlane as its alternative.
- There are no over-the-air updates. EAS Update has no counterpart here, and a fix goes through a store review.
- The lanes and the workflow were never run against real accounts, and `ios` and `android` have never executed in CI. The configuration is validated by `release_test.dart` only.
- The bundle identifier and application id (`com.boardroom.flutterdemo`) are placeholders of the demo.

## Alternatives considered

- **Codemagic.** A hosted Flutter CI with signing and publishing built in, and the closest thing to EAS. It would put the pipeline in another service's configuration instead of in the repository, and it could not be run or reviewed here without an account.
- **GitHub Actions calling `flutter build` and the store APIs directly.** No extra tool, and every concern of Fastlane (keychain, profiles, numbering, upload) written by hand.
- **Fastlane with `match`.** The usual team setup; rejected for one app, see above.
- **A tag that builds and uploads without a secret check.** One push would ship, or fail halfway; the gate makes the unconfigured case a skip.
