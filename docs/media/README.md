# Media of the README

The images and the GIF of the README, taken from the real app (the development configuration, whose
server is simulated) running on an iOS simulator.

| File | Shows |
| --- | --- |
| `demo.gif` | The whole scenario: sign in, the meetings list, a meeting, a vote cast offline and waiting to be sent, back online with the synchronisation banner, a confidential document with its watermark. |
| `sign-in.png` | The sign-in screen with the demo account filled in. |
| `meeting.png` | A meeting with the resolution to vote on. |
| `offline-vote.png` | The offline banner, and the vote saved on the device, waiting to be sent. |
| `protected-document.png` | A confidential document: the "Protected screen" badge and the watermark over the PDF. |

## Regenerate

```sh
tool/media/capture.sh
```

Needs `patrol_cli` (see the README, "End-to-end tests"), `ffmpeg` and Xcode. It uses the simulator
"iPhone 17" (`MEDIA_IOS_DEVICE` gives the UDID of another one), and takes a few minutes (the build).
`MEDIA_KEEP_WORK=1` keeps the raw video, the raw screenshots and the log of the run.

The script puts the simulator in English with a clean status bar (9:41, full battery and bars), runs
`tool/media/capture_test.dart` with Patrol, records the screen with `xcrun simctl io recordVideo`
while the flow runs, takes the screenshots with `simctl` (XCTest leaves the password field and the
protected document out of its own), and converts them with ffmpeg (GIF 320 px wide, 10 fps, its own
palette, 29 seconds at most; PNGs 390 px wide). When it ends, it puts the simulator back as it found
it: language, status bar, app uninstalled, shut down.

The capture flow is not an end-to-end test: it lives in `tool/media/`, outside `integration_test/`,
so neither `patrol test` nor the end-to-end workflow runs it. Flutter cannot build a release app
for a simulator, so the app is a debug build; the flow covers the "DEBUG" ribbon, and the script switches off the name of the
test that Patrol writes in red at the top of the screen (`--no-label`), so that
neither shows in the pictures.
