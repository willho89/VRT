#!/usr/bin/env bash
# Desktop screenshot for CRT tuning.
# Usage: tools/shot.sh out.png "<title substring>" "<input script>" "<cam: dist,yaw,pitch[,x_mm,y_mm]>" [seconds]
# e.g.   tools/shot.sh /tmp/a.png "240p test" "1:a,2:a" "0.08,0,0,40,20" 6
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-$HOME/Applications/vrt-tools/godot/Godot_v4.7.2-stable_linux.x86_64}
OUT=$1; TITLE=$2; INPUT=${3:-}; CAM=${4:-1.4,0,0}; WHEN=${5:-8}
LOG=${OUT%.png}.log
rm -f "$OUT"
# New class_name scripts need the editor's class cache refreshed first.
CACHE=$ROOT/godot/.godot/global_script_class_cache.cfg
if [ ! -f "$CACHE" ] || [ -n "$(find "$ROOT/godot/scripts" -name '*.gd' -newer "$CACHE" -print -quit)" ]; then
  timeout 120 "$GODOT" --headless --editor --quit --path "$ROOT/godot" > /dev/null 2>&1
  touch "$CACHE"
fi
# Startup occasionally stalls before the renderer comes up; retry once.
for try in 1 2; do
  timeout -s INT $(( ${WHEN%.*} + 12 )) "$GODOT" --path "$ROOT/godot" -- "--launch=$TITLE" --menu=0 \
    "--input=$INPUT" "--cam=$CAM" "--shot=$OUT@$WHEN" > "$LOG" 2>&1
  [ -f "$OUT" ] && break
done
grep -E "SCRIPT ERROR|SHADER ERROR" "$LOG" | head -5
[ -f "$OUT" ] && echo "$OUT" || { echo "no screenshot (see $LOG)"; exit 1; }
