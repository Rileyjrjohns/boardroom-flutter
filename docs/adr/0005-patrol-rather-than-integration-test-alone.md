# 0005. Patrol rather than integration_test alone

- Status: Accepted
- Related: [0006](0006-fastlane-for-delivery.md), [0007](0007-a-dio-fixture-server-as-the-dev-backend-and-the-http-mock.md)

## Context

The React Native app runs six Maestro flows on the built app. The Flutter port needs end-to-end flows on a device, and at least the two reference scenarios of the other app: biometric login, the list and a confidential document; an offline vote and its resynchronisation. The first scenario sends the app to the background for longer than the grace period of the lock (30 seconds) and comes back, which no Dart widget test can do: the operating system has to be driven, not only the widget tree.

## Decision

[Patrol](https://patrol.leancode.co) 4 on top of `integration_test` (`patrol` in `dev_dependencies`, `patrol_cli` 4.8.0 from `dart pub global activate`).

- **Two flows in `integration_test/`**, with the steps and test ids of the Maestro flows of the React Native app (`docs/spec/screens.md`): `biometric_login_list_document_test.dart` and `offline_vote_resync_test.dart`. The steps they share are in `integration_test/support`, and the test ids come from the constants of the app, so a renamed id breaks the build and not just the run.
- **Native automation where Dart cannot reach.** `leaveAppFor` presses home (`$.platform.mobile.pressHome()`), waits 35 seconds and reopens the app (`openApp()`), each bounded by a timeout.
- **Native setup is committed:** the instrumentation runner and test orchestrator in `android/app/build.gradle.kts` and `MainActivityTest.java`, the `RunnerUITests` target on iOS, and the `patrol:` section of `pubspec.yaml`.
- **Development configuration.** The flows run with `--dart-define=BOARDROOM_ADAPTERS=dev`, so there is no backend to start ([0007](0007-a-dio-fixture-server-as-the-dev-backend-and-the-http-mock.md)).
- **CI.** `.github/workflows/e2e.yml` boots an Android 34 emulator and runs `patrol test` through `tool/ci/e2e_android.sh`, by hand and on a version tag, not on every pull request (several minutes). iOS is not run in CI.

## Consequences

- Both device flows are the same scenarios as the other app's, so the two apps are compared on behaviour, with the same test ids.
- The tests are Dart, in the same language and with the same finders as the widget tests, which Maestro's YAML is not. The cost is a native setup per platform and a CLI to install.
- `integration_test/` is not run by `flutter test`, so the checks of a pull request stay fast; the flows are a separate workflow, and a break shows on a tag or a manual run, not on every change.
- On a device with a fingerprint or a face enrolled the system prompt appears and the first flow cannot answer it, so it runs on a device with nothing enrolled (the biometric gate is then the simulated one).
- The two flows are not the six of the Maestro suite. That is a choice of scope, written in the README, not a hidden gap.

## Alternatives considered

- **`integration_test` alone.** Part of Flutter, nothing to install, but no access to the operating system: no home button, no permission dialog, no notification shade. The lock-on-resume flow could not be written.
- **Maestro, as in the React Native app.** Same flows in the same YAML for both apps, and it was available. It drives the app through its accessibility tree from outside; Patrol keeps the flows in Dart, with the same finders and the test-id constants of the app, in the toolchain a Flutter team already has.
- **Appium or Flutter Driver.** Flutter Driver is deprecated in favour of `integration_test`; Appium adds a server and a driver for two flows.
- **Golden and widget tests only.** They exist ([README](../../README.md#tests)) and prove the screens, not the app on a device with its lifecycle.
