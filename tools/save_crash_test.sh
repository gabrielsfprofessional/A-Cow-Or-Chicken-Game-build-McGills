#!/usr/bin/env bash
# Crash test for the server's player saves (card T21, part 1). Owner: Gabe.
# Starts tests/save_crash_writer.gd, which saves players in a loop, hard-kills it at a
# random moment, then runs tests/save_crash_check.gd: no player that loaded before may be
# gone or go backwards, every save on disk must load, and no file may need moving aside.
# Repeats KILLS times on one temp folder, then removes it.
# A hard kill is what a crashed or killed server does. A pulled plug can also lose
# data the OS hadn't written yet; tests/profile_store_test.gd covers that with a
# cut-short file.
# Usage (Linux, CI, or Git Bash):  GODOT=/path/to/godot bash tools/save_crash_test.sh [KILLS] [PLAYERS]
# On Windows, tools/save_crash_test.ps1 does the same with taskkill.
set -uo pipefail
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KILLS="${1:-20}"
PLAYERS="${2:-8}"
WORK="$(mktemp -d)"
SAVES="$WORK/saves"
PID=""
stop_writer() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    # Git Bash: the console build starts a child, so kill the Windows tree too.
    if [ -r "/proc/$PID/winpid" ]; then taskkill //F //T //PID "$(cat "/proc/$PID/winpid")" >/dev/null 2>&1; fi
    kill -9 "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
  fi
  PID=""
}
cleanup() { stop_writer; rm -rf "$WORK"; }
trap cleanup EXIT
# The writer and the check need the class cache to know ProfileStore, as smoke does.
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1
for k in $(seq 1 "$KILLS"); do
  WLOG="$WORK/writer.log"
  "$GODOT" --headless --path "$ROOT" --script res://tests/save_crash_writer.gd -- "--saves=$SAVES" "--players=$PLAYERS" --writer-limit-sec=60 >"$WLOG" 2>&1 &
  PID=$!
  STARTED=$SECONDS
  until grep -q "\[SaveCrash\] writing" "$WLOG" 2>/dev/null; do
    if ! kill -0 "$PID" 2>/dev/null || [ $((SECONDS - STARTED)) -ge 20 ]; then
      tail -n 20 "$WLOG"
      echo "SAVE CRASH: FAIL: the writer never started (kill $k)"
      exit 1
    fi
    sleep 0.1
  done
  # 0.1 to 1.5 s into the saving loop.
  sleep "$(awk -v r="$RANDOM" 'BEGIN { printf "%.2f", 0.1 + (r % 141) / 100 }')"
  stop_writer
  CLOG="$WORK/check.log"
  if ! "$GODOT" --headless --path "$ROOT" --script res://tests/save_crash_check.gd -- "--saves=$SAVES" "--players=$PLAYERS" >"$CLOG" 2>&1; then
    tail -n 30 "$CLOG"
    echo "SAVE CRASH: FAIL after kill $k of $KILLS"
    exit 1
  fi
  if grep -qE "SCRIPT ERROR|Parse Error" "$CLOG" "$WLOG"; then
    grep -nE "SCRIPT ERROR|Parse Error" "$CLOG" "$WLOG"
    echo "SAVE CRASH: FAIL: script error (kill $k)"
    exit 1
  fi
  echo "kill $k/$KILLS: $(grep -o 'SAVE CRASH CHECK: .*' "$CLOG")"
done
echo "SAVE CRASH: PASS ($KILLS kills, $PLAYERS players)"
