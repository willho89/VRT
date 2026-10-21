#!/usr/bin/env bash
# Fetch the libretro cores VRT bundles into cores/<platform>/ (gitignored).
# Android cores are packed into the APK (godot/cores_bundle -> user://retro/cores
# on first run); Linux cores are used by the desktop flat mode.
# DeeVee is our own core: taken from a local DeeVee checkout's build output.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEEVEE=${DEEVEE_DIR:-$HOME/.claude/projects/DeeVee}
BUILDBOT=https://buildbot.libretro.com/nightly
# Quest 2 baseline set (8/16-bit). Quest 3 additions come later.
CORES=(fceumm snes9x genesis_plus_gx mednafen_pce_fast ffmpeg pcsx_rearmed parallel_n64)

fetch() { # platform url-dir suffix
  local dest=$ROOT/cores/$1; mkdir -p "$dest"
  local tmp; tmp=$(mktemp -d)
  for c in "${CORES[@]}"; do
    local f=${c}${3}
    if [ ! -f "$dest/$f" ]; then
      curl -sSfL -o "$tmp/$f.zip" "$BUILDBOT/$2/$f.zip"
      unzip -oq "$tmp/$f.zip" -d "$dest"
      echo "fetched $1/$f"
    fi
  done
  rm -rf "$tmp"
}
fetch linux-x86_64 linux/x86_64/latest _libretro.so
fetch android-arm64 android/latest/arm64-v8a _libretro_android.so

cp -u "$DEEVEE/build/android-arm64/deevee_libretro_android.so" "$ROOT/cores/android-arm64/" 2>/dev/null \
  || echo "warning: no DeeVee android-arm64 build in $DEEVEE"
cp -u "$DEEVEE/deevee_libretro.so" "$ROOT/cores/linux-x86_64/" 2>/dev/null \
  || echo "warning: no DeeVee linux build in $DEEVEE"

# Only DeeVee ships inside the APK; VRT downloads every other core from the
# libretro buildbot on first need (CoreDownloader), so the release carries no
# third-party cores (Snes9x and Genesis Plus GX are non-commercial licences).
# The DeeVee build must be DEEVEE_CSS=dlopen (no CSS code; libdvdcss is
# user-supplied in its system folder).
mkdir -p "$ROOT/godot/cores_bundle"
rm -f "$ROOT"/godot/cores_bundle/*.so
cp "$ROOT/cores/android-arm64/deevee_libretro_android.so" "$ROOT/godot/cores_bundle/"
ls -la "$ROOT/cores/"*
