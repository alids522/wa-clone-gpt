#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../android"
collect_logs() {
  mkdir -p ../build/app/reports/androidTests
  adb logcat -d > ../build/app/reports/androidTests/call-logcat.txt || true
  adb shell dumpsys activity activities > ../build/app/reports/androidTests/activity-state.txt || true
}
trap collect_logs EXIT
./gradlew app:connectedDebugAndroidTest \
  -Pdart-defines=RklSRUJBU0VfRU5BQkxFRD10cnVl \
  -Ptarget-platform=android-x64
