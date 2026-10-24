#!/usr/bin/env bash
# Runs the Patrol flows on the Android emulator that is already booted, and keeps what is needed to
# understand a failure in build/e2e-logs/: the logcat of the whole run, the output of patrol, and,
# when the run does not end in time, a screenshot and the list of processes.
set -u

readonly logs=build/e2e-logs
readonly limit=20m
mkdir -p "$logs"

adb logcat -c
adb logcat -v threadtime > "$logs/logcat.txt" 2>&1 &
logcat_pid=$!

# `timeout` ends patrol if it hangs; --verbose prints the Gradle and instrumentation output.
timeout --signal=TERM --kill-after=30s "$limit" \
  patrol test --verbose --dart-define=BOARDROOM_ADAPTERS=dev "$@" 2>&1 | tee "$logs/patrol.txt"
status=${PIPESTATUS[0]}

if [ "$status" -ne 0 ]; then
  echo "Patrol ended with status $status; collecting the state of the device."
  adb exec-out screencap -p > "$logs/screen.png" 2> /dev/null || true
  adb shell ps -A > "$logs/processes.txt" 2>&1 || true
  adb shell dumpsys activity activities > "$logs/activities.txt" 2>&1 || true
fi

kill "$logcat_pid" 2> /dev/null || true
exit "$status"
