#!/usr/bin/env bash
# Makes the media of the README (docs/media) from the real app on an iOS simulator: it runs the
# capture flow (tool/media/capture_test.dart) with Patrol, records the screen with `simctl` while the
# flow runs, takes the screenshots with `simctl` when the flow asks for them, and converts them with
# ffmpeg (a GIF with its own palette, and small PNGs).
#
#   tool/media/capture.sh
#
# Not part of the end-to-end suite (the flow is outside integration_test/, so `patrol test` and the
# e2e workflow never run it). Needs patrol_cli, ffmpeg and Xcode on the PATH, and a simulator:
# MEDIA_IOS_DEVICE is its UDID (default: the "iPhone 17" of the maintainers). The app is a debug
# build with the development configuration (the simulated server): Flutter cannot build a release
# or profile app for a simulator. The flow therefore covers the debug ribbon itself (see capture_test.dart), and the name of
# the test that Patrol writes on the screen is switched off.
# MEDIA_KEEP_WORK=1 keeps the raw video, the raw screenshots and the log of the run, for a look.
#
# The script changes the simulator for the run, and puts it back as it found it when it ends,
# whatever happens: the language (the README is in English; the simulator is shut down to change it),
# the status bar (9:41, full battery, full bars), the app (uninstalled), and the state (shut down if
# it was shut down).
set -euo pipefail

cd "$(dirname "$0")/../.."

UDID="${MEDIA_IOS_DEVICE:-D78B6DD3-4305-4B9E-B163-03A83A836303}"
BUNDLE_ID="com.boardroom.flutterdemo"
OUT_DIR="docs/media"
GIF_WIDTH=320
GIF_FPS=10
GIF_MAX_SECONDS=29
PNG_WIDTH=390

PREFS="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/Preferences/.GlobalPreferences"
WORK="$(mktemp -d)"
RECORDING_PID=""

# What the simulator was before: its state, and the language (a missing key is remembered as such).
WAS_BOOTED=0
if xcrun simctl list devices booted | grep -q "$UDID"; then WAS_BOOTED=1; fi
read_pref() { defaults read "$PREFS" "$1" 2>/dev/null || true; }
LANGUAGES_BEFORE="$(defaults read "$PREFS" AppleLanguages 2>/dev/null | tr -d '() \n"' || true)"
LOCALE_BEFORE="$(read_pref AppleLocale)"

restore() {
  if [[ -n "$RECORDING_PID" ]]; then
    kill -INT "$RECORDING_PID" 2>/dev/null || true
    wait "$RECORDING_PID" 2>/dev/null || true
  fi
  xcrun simctl status_bar "$UDID" clear 2>/dev/null || true
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID.RunnerUITests.xctrunner" 2>/dev/null || true
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  if [[ -n "$LANGUAGES_BEFORE" ]]; then
    defaults write "$PREFS" AppleLanguages -array "$LANGUAGES_BEFORE"
  else
    defaults delete "$PREFS" AppleLanguages 2>/dev/null || true
  fi
  if [[ -n "$LOCALE_BEFORE" ]]; then
    defaults write "$PREFS" AppleLocale -string "$LOCALE_BEFORE"
  else
    defaults delete "$PREFS" AppleLocale 2>/dev/null || true
  fi
  if [[ "$WAS_BOOTED" == 1 ]]; then xcrun simctl boot "$UDID" 2>/dev/null || true; fi
  if [[ -n "${MEDIA_KEEP_WORK:-}" ]]; then
    echo "Raw video, screenshots and log kept in $WORK"
  else
    rm -rf "$WORK"
  fi
}
trap restore EXIT

mkdir -p "$OUT_DIR"

# English: the language is read at boot, so the simulator is shut down first.
xcrun simctl shutdown "$UDID" 2>/dev/null || true
defaults write "$PREFS" AppleLanguages -array en
defaults write "$PREFS" AppleLocale -string en_US
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override \
  --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3

# The flow writes `media` steps in the output of Patrol: the video runs from `start` to `end`, and a screenshot of simctl is
# taken at each `shot`. Patrol builds the app first, which takes minutes and is no part of the video.
patrol test -d "$UDID" --target tool/media/capture_test.dart --dart-define=BOARDROOM_ADAPTERS=dev \
  --no-label 2>&1 |
  tee "$WORK/patrol.log" |
  while IFS= read -r line; do
    case "$line" in
      *"⏳"*'media'*'"start"'*)
        [[ -e "$WORK/recording.pid" ]] && continue
        xcrun simctl io "$UDID" recordVideo --codec h264 --force "$WORK/video.mov" >"$WORK/recording.log" 2>&1 &
        echo $! >"$WORK/recording.pid"
        until grep -q "Recording started" "$WORK/recording.log"; do sleep 0.1; done
        ;;
      *"⏳"*'media'*'"shot '*)
        name="${line##*\"shot }"
        name="${name%%\"*}"
        xcrun simctl io "$UDID" screenshot "$WORK/$name.png" >/dev/null 2>&1
        ;;
      *"⏳"*'media'*'"end"'*)
        kill -INT "$(cat "$WORK/recording.pid")" 2>/dev/null || true
        sleep 2
        ;;
    esac
  done

for f in video.mov sign-in.png meeting.png offline-vote.png protected-document.png; do
  [[ -s "$WORK/$f" ]] || { echo "The flow did not produce $f (log: $WORK/patrol.log)" >&2; MEDIA_KEEP_WORK=1; exit 1; }
done

DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/video.mov")"
SPEED="$(awk -v d="$DURATION" -v m="$GIF_MAX_SECONDS" 'BEGIN { s = d / m; print (s < 1 ? 1 : s) }')"

# The palette is made for this video alone, and only the pixels that change are redrawn.
ffmpeg -y -loglevel error -i "$WORK/video.mov" \
  -vf "setpts=PTS/$SPEED,fps=$GIF_FPS,scale=$GIF_WIDTH:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  "$OUT_DIR/demo.gif"

for name in sign-in meeting offline-vote protected-document; do
  ffmpeg -y -loglevel error -i "$WORK/$name.png" -vf "scale=$PNG_WIDTH:-1:flags=lanczos" "$OUT_DIR/$name.png"
done

ls -l "$OUT_DIR"
