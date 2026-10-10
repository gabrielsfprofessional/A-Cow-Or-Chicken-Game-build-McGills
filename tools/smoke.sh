#!/usr/bin/env bash
# Smoke test: import the project, run the game headless for 300 frames and fail
# if Godot prints any script or engine error. Then run every tests/*_test.gd and
# Adam's arena checks (when they exist) and fail if any exits non-zero.
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

# Script tests. Each one prints its own cases and exits 1 on a failure. Their own
# logs are judged by exit code and script errors only: a test may provoke an
# engine error on purpose.
SCRIPTS=()
for f in "$ROOT"/tests/*_test.gd; do
  [ -e "$f" ] && SCRIPTS+=("res://tests/$(basename "$f")")
done
for f in game/maps/tools/check_arena.gd game/maps/tools/test_arena_check.gd; do
  [ -e "$ROOT/$f" ] && SCRIPTS+=("res://$f")
done
FAILED=0
for s in "${SCRIPTS[@]}"; do
  SLOG="$(mktemp)"
  "$GODOT" --headless --path "$ROOT" --script "$s" >"$SLOG" 2>&1
  CODE=$?
  if [ "$CODE" -ne 0 ] || grep -qE "SCRIPT ERROR|Parse Error" "$SLOG"; then
    cat "$SLOG"
    echo "SMOKE: $s FAILED (exit $CODE, log: $SLOG)"
    FAILED=$((FAILED + 1))
  else
    echo "SMOKE: $s passed"
  fi
done
if [ "$FAILED" -gt 0 ]; then
  echo "SMOKE: FAIL ($FAILED script(s) failed)"
  exit 1
fi
echo "SMOKE: PASS"
