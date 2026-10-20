#!/usr/bin/env bash
# Build a tester APK: builds/VRT-<version>-<commit>.apk (debug-signed, sideload only).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GODOT=$HOME/Applications/vrt-tools/godot/Godot_v4.7.2-stable_linux.x86_64
VER=$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/godot/project.godot")
SHA=$(git -C "$ROOT" rev-parse --short HEAD)
OUT=$ROOT/builds/VRT-$VER-$SHA.apk
mkdir -p "$ROOT/builds"
"$GODOT" --headless --path "$ROOT/godot" --install-android-build-template \
  --export-debug "Meta Quest" "$OUT" 2>&1 | grep -E "ERROR|SCRIPT ERROR" | grep -v "project icon" || true
ls -la "$OUT"
