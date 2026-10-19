#!/usr/bin/env bash
# Export the debug APK, install it on the connected headset and launch it.
# Usage: tools/deploy.sh [--no-export]
set -euo pipefail
TOOLS=${VRT_TOOLS:-$HOME/Applications/vrt-tools}
GODOT=$TOOLS/godot/Godot_v4.7.2-stable_linux.x86_64
ADB=$TOOLS/android-sdk/platform-tools/adb
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APK=$ROOT/builds/vrt-debug.apk
PKG=io.github.willho89.vrt

if [ "${1:-}" != "--no-export" ]; then
  mkdir -p "$ROOT/builds"
  "$GODOT" --headless --path "$ROOT/godot" --install-android-build-template \
    --export-debug "Meta Quest" "$APK" 2>&1 | grep -E "ERROR|SCRIPT ERROR" || true
fi
"$ADB" install -r "$APK" | tail -1
"$ADB" logcat -c
"$ADB" shell am force-stop $PKG
"$ADB" shell am start -n $PKG/com.godot.game.GodotAppLauncher >/dev/null

# Save Godot + runtime perf logs for the whole session so they survive the app
# being closed or logcat rotating. Stops when the headset disconnects or on kill.
pkill -f "logcat -v time godot" 2>/dev/null || true
mkdir -p "$ROOT/builds/logs"
LOG=$ROOT/builds/logs/$(date +%Y%m%d-%H%M%S).log
setsid nohup "$ADB" logcat -v time godot:* VrApi:I '*:S' > "$LOG" 2>&1 < /dev/null &
ln -sf "$LOG" "$ROOT/builds/logs/latest.log"
echo "Launched. Logging to $LOG (builds/logs/latest.log)"
