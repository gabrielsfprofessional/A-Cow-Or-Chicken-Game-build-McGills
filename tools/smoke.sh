#!/usr/bin/env bash
# Smoke test v0: import the project, run the game headless for 300 frames,
# and fail if Godot prints any script or engine error.
# Usage (Linux, CI, or Git Bash):  GODOT=/path/to/godot bash tools/smoke.sh
# Gabe extends this in card T09 to also start the server and 2 test bots.
set -uo pipefail
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$(mktemp)"
"$GODOT" --headless --path "$ROOT" --import >"$LOG" 2>&1
"$GODOT" --headless --path "$ROOT" --quit-after 300 >>"$LOG" 2>&1
if grep -nE "SCRIPT ERROR|Parse Error|ERROR:" "$LOG"; then
  echo "SMOKE: FAIL (full log: $LOG)"
  exit 1
fi
echo "SMOKE: PASS"
