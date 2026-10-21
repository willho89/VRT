#!/usr/bin/env bash
# Switch the headset's adb to Wi-Fi (needs USB once; again after each headset
# reboot, which turns network adb off). Remembers the address in
# builds/quest-addr for deploy.sh, which reconnects after every export (a
# Godot export restarts the adb server and drops wireless connections).
set -euo pipefail
ADB=${VRT_TOOLS:-$HOME/Applications/vrt-tools}/android-sdk/platform-tools/adb
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IP=$("$ADB" -d shell ip -f inet addr show wlan0 | sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p')
[ -n "$IP" ] || { echo "Headset has no Wi-Fi address (is it on Wi-Fi?)"; exit 1; }
"$ADB" -d tcpip 5555 >/dev/null
sleep 2
"$ADB" connect "$IP:5555"
mkdir -p "$ROOT/builds"
echo "$IP:5555" > "$ROOT/builds/quest-addr"
echo "Wireless adb on $IP:5555. You can unplug the cable."
