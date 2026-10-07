#!/usr/bin/env bash
# App Store screenshots from the iOS simulator (6.9" class by default).
# Usage: tool/ios_store_screenshots.sh ["iPhone 18 Pro Max"] [out_dir]
# Runs integration_test/app_store_screenshots_test.dart and captures the
# simulator each time the test prints SHOT_READY <name>.
set -euo pipefail
DEVICE_NAME="${1:-iPhone 18 Pro Max}"
OUT="${2:-store/screenshots/ios-6.9}"
UDID=$(xcrun simctl list devices available | grep -F "$DEVICE_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "no simulator named $DEVICE_NAME"; exit 1; }
mkdir -p "$OUT"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
LOG=$(mktemp)
flutter test integration_test/app_store_screenshots_test.dart -d "$UDID" >"$LOG" 2>&1 &
PID=$!
seen=""
while kill -0 "$PID" 2>/dev/null; do
  for name in $(grep -oE 'SHOT_READY [0-9a-z-]+' "$LOG" | awk '{print $2}'); do
    case " $seen " in *" $name "*) continue ;; esac
    sleep 1
    xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
    echo "captured $name"
    seen="$seen $name"
  done
  sleep 0.5
done
wait "$PID" && status=0 || status=$?
tail -3 "$LOG"
xcrun simctl status_bar "$UDID" clear
exit "$status"
