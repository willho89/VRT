#!/usr/bin/env bash
# Test content for CRT calibration (gitignored): 240p Test Suite NES port (GPL-2.0,
# pinobatch/240p-test-mini). Lands in testdata/roms/NES/, which the desktop build
# scans; tools/deploy.sh --testdata pushes it to the headset.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/testdata/roms/NES"
curl -sSfL -o "$ROOT/testdata/roms/NES/240p Test Suite.nes" \
  https://github.com/pinobatch/240p-test-mini/releases/download/v0.23/240pee.nes
ls -la "$ROOT/testdata/roms/NES"
