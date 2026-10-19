#!/usr/bin/env bash
# Build the libretro host GDExtension (extension/libretro-godot, our fork) into
# godot/addons/libretro_godot/bin. Runs SCons inside the vrtbuild distrobox.
# Usage: tools/build_extension.sh [linux|android|all] [debug|release]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WHICH=${1:-all}
TARGET=template_${2:-debug}
NDK=${ANDROID_NDK_ROOT:-$HOME/Applications/vrt-tools/android-sdk/ndk/29.0.14206865}
OUT=$ROOT/godot/addons/libretro_godot/bin
mkdir -p "$OUT"

run() {
  if [ -e /run/.containerenv ]; then bash -c "$1"; else distrobox enter vrtbuild -- bash -c "$1"; fi
}
cd "$ROOT/extension/libretro-godot"
if [ "$WHICH" = linux ] || [ "$WHICH" = all ]; then
  run "LIBRETRO_GODOT_OUTPUT_DIR='$OUT' scons -j\$(nproc) platform=linux arch=x86_64 target=$TARGET"
fi
if [ "$WHICH" = android ] || [ "$WHICH" = all ]; then
  run "LIBRETRO_GODOT_OUTPUT_DIR='$OUT' ANDROID_NDK_ROOT='$NDK' ANDROID_HOME='' scons -j\$(nproc) platform=android arch=arm64 target=$TARGET"
fi
ls -la "$OUT"
