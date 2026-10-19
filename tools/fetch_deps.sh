#!/usr/bin/env bash
# Fetch third-party binaries that are not committed (pinned versions).
set -euo pipefail
VENDORS_VER=5.1.0-stable
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/godot/addons/godotopenxrvendors"
if [ ! -f "$DEST/plugin.gdextension" ]; then
  tmp=$(mktemp -d)
  curl -sSL -o "$tmp/vendors.zip" \
    "https://github.com/GodotVR/godot_openxr_vendors/releases/download/$VENDORS_VER/godotopenxrvendorsaddon.zip"
  unzip -q "$tmp/vendors.zip" -d "$tmp"
  mkdir -p "$ROOT/godot/addons"
  cp -r "$tmp/asset/addons/godotopenxrvendors" "$ROOT/godot/addons/"
  rm -rf "$tmp"
  echo "Installed godot_openxr_vendors $VENDORS_VER"
fi
