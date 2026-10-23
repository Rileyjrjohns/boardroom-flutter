# Native plugin: screen_protection

`packages/screen_protection` is a local Flutter plugin, in Kotlin and Swift, over a typed channel that Pigeon generates. It is the native half of the `ScreenProtection` port: it keeps a confidential screen out of the screenshots, the recordings and the app switcher as far as each platform allows, and it tells the app when a screenshot or a recording happens. It replaces the local Expo module `modules/screen-protection` of the React Native app, and keeps its behaviour and its limits.

The app depends on it by path (`screen_protection` in `pubspec.yaml`) and the two are one workspace (`workspace:` in the root `pubspec.yaml`), so one `flutter pub get` resolves both. Flutter autolinks it: an Android Gradle library and an iOS podspec (and a Swift package, for the day Swift Package Manager is turned on).

## What it does, per platform

| | Android | iOS |
| --- | --- | --- |
| Protection on | `FLAG_SECURE` on the window of the current activity, on the main thread. The system **blocks screenshots and screen recordings** of that window and shows **a blank thumbnail in the recent apps** | An opaque native view in the colour of the system background, with no text, is put over the windows of the scene **whenever it resigns active** (app switcher, control centre, a system prompt) and taken away when it becomes active again (`UIScene.willDeactivateNotification` and `didActivateNotification`: the app is scene based). It does not block screenshots or recordings: iOS has no public API for that (see the secure view) |
| Protection off | The flag is cleared | No cover |
| Secure content | A plain container: `FLAG_SECURE` already keeps the whole window out of captures | The secure view sets the private `disableUpdateMask` flag on the Flutter view (see below) |
| Screenshot taken | `Activity.ScreenCaptureCallback`, Android 14 (API 34) and later, with the `DETECT_SCREEN_CAPTURE` permission | `UIApplication.userDidTakeScreenshotNotification` |
| Recording started or stopped | `WindowManager.addScreenRecordingCallback`, Android 15 (API 35) and later, with the `DETECT_SCREEN_RECORDING` permission | The capture state of the scenes on iOS 17 and later (`UITraitCollection.sceneCaptureState`, observed with `registerForTraitChanges`), `UIScreen.isCaptured` and `UIScreen.capturedDidChangeNotification` before iOS 17 and for a scene that has no state. It covers recording, mirroring and AirPlay |
| "Is it captured now" | The state of the recording callback on Android 15 and later; `false` before | The same sources as above |
| Capabilities | `protection` everywhere, `screenshotDetection` from 14, `recordingDetection` from 15, no `secureView` | All four |

**Limits, stated plainly.**

- iOS has no public way to block a screenshot or a recording. What the app does there is the cover in the app switcher, the events (it learns of a capture after the fact) and the secure view, which relies on an undocumented flag. A photograph of the screen is not affected.
- Android before 14 has **no screenshot detection**, and before 15 **no recording detection**: the system tells apps nothing there, the plugin reports nothing (`capabilities()` says so), and the protection itself works on every version. A build without the two permissions has the detection off: the plugin catches the `SecurityException`.
- `FLAG_SECURE` belongs to one window. A window of its own over the app (a system dialog) is not covered by the flag of the activity.
- The iOS cover is also up while a system prompt (Face ID) is on screen, because the scene is then inactive, and only while the protection is on.
- Not ported from React Native: the clearing of the text selection of a `PDFView`. It belongs to the PDF viewer, which this port has not chosen yet; when it does, the same observer goes in the plugin, or in the viewer.
- Nothing was run on a device by this change. What was verified is in [What was verified](#what-was-verified).

**The events.** One stream of typed messages: `ScreenshotTakenMessage` (no payload) and `CaptureChangedMessage(captured)`, sent when the state changes and not repeated. The adapter maps them to the three `ScreenCaptureKind` of the port (`screenshotTaken`, `recordingStarted`, `recordingStopped`) and reads `isCaptured` once when it starts listening, so a document opened during a recording knows about it.

**Why the cover is on only while the protection is on.** Same decision as the React Native app: the plugin is a mechanism and the policy belongs to the application layer (`ScreenProtectionCoordinator`), which decides which screens need the protection and turns the switch on and off. Covering the whole app would be a change there (acquire for the length of the session), not in a native file.

**Robustness.**

- All state is read and written on the main thread. Pigeon runs the asynchronous calls there (a suspend function on `Dispatchers.Main`, a `@MainActor` task), so `setProtectionEnabled` completes after the change is made.
- No activity, no window: on Android, turning the protection on with no activity only remembers it, and the flag is set on the window of the activity the plugin gets (`ProtectionState`). The window is replaced when the system recreates the activity (rotation, font size, theme): the plugin follows it (`ActivityAware`).
- The listeners of the system (the screenshot callback, the recording callback, the notifications and the trait observers) exist only while Dart listens to the stream, and are all removed when it stops, and when the plugin is detached from the engine, which also turns the protection off and leaves the window as found.
- Idempotent: on twice, off twice, off when it is off.
- The two Android permissions are declared in the manifest of the plugin and merged into the one of the app. Both are normal permissions, granted at install. iOS needs no `Info.plist` entry and shows no text.

## The secure view (iOS)

`SecureView` (`package:screen_protection/screen_protection_view.dart`) is the widget of the plugin: a container of a child that is left out of captures while `secure` is on.

- **Android.** The child as it is: the window flag does the work.
- **iOS.** While `secure` is on, a native view (a `UiKitView` of 1 x 1 logical pixels, transparent, with no touch) is mounted next to the child. While it is in a window, it sets the private Core Animation property `disableUpdateMask` (the value `(1 << 1) | (1 << 4)`) on a layer, through key-value coding, and only when the layer answers to `setDisableUpdateMask:`. It is the flag UIKit sets for a secure text field, and the reason such a field is left out of captures. When the widget is removed, or `secure` goes off, the layer is shown again, once the last secure view holding it has gone (`CaptureExclusionRegistry` counts them).
- **Which layer: the difference from React Native.** In React Native the children of the view are native views, so the view marks its own layer and its subtree is left out. Flutter draws every widget into one surface (the Flutter view), so a widget cannot be a native subview of a platform view. The native view therefore marks the Flutter view, the top view of its window: **everything Flutter draws is left out of captures while a secure view is mounted**, not only the child. The widget is mounted only while the content is on screen, which is how long it matters. If a native PDF view (a `PlatformView` that draws the document itself) is chosen for the viewer, the flag could be set on that view's layer alone instead, which is narrower.
- **Fallback.** When the layer has no such property, the content is visible in captures, nothing crashes, and the case is reported: an event on a stream of its own (so that listening to it starts no capture detection), which reaches `SecureView.onFallback` with a reason, and a line in the system log under the subsystem `com.boardroom.screenprotection`.
- **It is undocumented behaviour.** The property is private to Core Animation: App Review may object to it, and an iOS update may change or remove it. It is the piece that really hides a confidential document on iOS: it was verified on a real iPhone in the React Native app, where the view marked its own layer. **It has not been run in this Flutter plugin yet**: whether marking the Flutter view has the same effect is the first thing to try on a device (the demo screen does it: turn the protection on, take a screenshot, look at it).

## How it plugs into the architecture

- **The port.** `lib/features/documents/application/ports/screen_protection.dart` is the port (`enable`, `disable`, `subscribe`; results, no exception crosses it). `NativeScreenProtection` (`lib/features/documents/infrastructure/native/native_screen_protection.dart`) implements it over `ScreenProtectionModuleApi`, the seam of the adapter; `PigeonScreenProtectionModule` is the seam over the typed channel; `loadScreenProtectionModule()` gives it on Android and iOS and nothing elsewhere. `main.dart` builds the adapter. Same behaviour as `NativeScreenProtection.ts`:
  - calls go to the native side one at a time, in the order issued, each bounded in time (5 s); a failure is `screenProtectionFailed` (and the monitoring hears `screenProtectionNativeFailed`, with the code of the failure when it is written like a code, and nothing else); no native side (the platform has no plugin) is `screenProtectionUnsupported` for `enable`, and success for `disable`;
  - one native listener for all the subscribers, only while someone is subscribed; a change is told once; a recording already running when someone subscribes is told to them as `recordingStarted`;
  - a listener that throws is reported (`screenProtectionListenerFailed`) and does not stop the others.
- **The import rule.** Only `infrastructure` (and `app`) may import `package:screen_protection`: it is in `adapterPackages` of `tool/check_imports.dart`. One exception, the secure view.
- **`SecureContent`, and why it is the exception.** `lib/features/documents/presentation/secure_content.dart` wraps `SecureView` and is the one file of the presentation that imports the plugin, and only `screen_protection_view.dart`. `presentationExemptions` in the checker lists that file and that URI, nothing else, and `test/tool/check_imports_test.dart` tests it both ways (the lint rule of React Native, in the same spirit). The other option was a widget in `infrastructure/` that composition hands to the screens. It was not chosen: a native view is an element of the widget tree, and no port, which carries data and calls, can pass one; handing a builder down needs a provider that does not exist before the router of step 5, and a screen that receives a builder is no easier to read than one that names `SecureContent`. The exemption costs one line of the checker, is checked, and keeps the widget where the screens look for it.
- **The demo screen.** `ScreenProtectionDemoScreen` (reached from the placeholder home screen until the router): a switch, a `SecureContent` with a confidential sample text, and the list of the captures received. It drives the port directly, as a demo: the real documents go through the coordinator, which counts the screens that need the protection.

## The typed channel and how it is regenerated

`packages/screen_protection/pigeons/screen_protection_api.dart` declares the API once: `ScreenProtectionHostApi` (`setProtectionEnabled`, `isCaptured`, `capabilities`), the messages (`ProtectionCapabilities`, the sealed `CaptureEventMessage`, `SecureLayerFallbackMessage`) and `ScreenProtectionEvents` (two event channels). Pigeon writes `lib/src/messages.g.dart`, `android/.../Messages.g.kt` and `ios/.../Messages.g.swift`. They are **committed**, because the native builds need them (the one exception to the rule that `*.g.dart` is generated and not committed: `.gitignore` says so). Pigeon is a dev dependency of the plugin, and nothing else uses it.

To regenerate after a change of the API (from the root of the repository):

```sh
cd packages/screen_protection
dart run pigeon --input pigeons/screen_protection_api.dart
dart format lib
```

CI runs the same commands and fails if `git diff` is not empty afterwards, so a change of the API without the regenerated files, or a hand edit of a generated file, cannot be merged.

## What was verified

| | |
| --- | --- |
| Dart | Tests of the adapter (the 36 scenarios of React Native, same names but one, and the contract suite), of the module over a fake of the generated host API, of the demo screen, of `SecureView` and of the generated channel over a mocked messenger (see [`parity/infrastructure.md`](parity/infrastructure.md)) |
| Kotlin | JVM unit tests of the logic that needs no device: `ProtectionState`, `CaptureStateTracker`, `Capabilities` (`cd android && ./gradlew :screen_protection:testDebugUnitTest`) |
| Swift | XCTest of `CaptureDecision` and `CaptureMask` in `ios/screen_protection/Tests`, which need an iOS simulator (the target imports Flutter): they were run on macOS in a scratch package with the same files, 6 tests; they are not run by CI |
| Native builds | `flutter build apk --debug` and `flutter build ios --simulator --debug --no-codesign` compile the Kotlin and the Swift |
| **Not verified** | Everything that needs a device: `FLAG_SECURE` on a real window, the Android 14 and 15 callbacks, the app switcher cover, the screenshot and recording detection on iOS, and above all the secure view on the Flutter view. No simulator, emulator or device was started. The first thing to try is the demo screen on an iPhone and on an Android 15 phone |
