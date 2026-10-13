#!/usr/bin/env bash
# Smoke test: import the project, run the game headless for 300 frames and fail
# if Godot prints any script or engine error. Then run every tests/*_test.gd and
# Adam's arena checks (when they exist) and fail if any exits non-zero or runs
# longer than 60 s (it is then killed). Then play a bot match (cards T09, T18): a headless server and 4 test bots, one per hero, on UDP 7777.
# Usage (Linux, CI, or Git Bash):  GODOT=/path/to/godot bash tools/smoke.sh
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
# engine error on purpose. Each gets SCRIPT_LIMIT_SEC; one still running then is
# killed (KILL 5 s after TERM) and fails as timed out, so a hung test can't hang
# smoke.
SCRIPT_LIMIT_SEC=60
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
  timeout --kill-after=5s "${SCRIPT_LIMIT_SEC}s" "$GODOT" --headless --path "$ROOT" --script "$s" >"$SLOG" 2>&1
  CODE=$?
  # 124: timeout stopped it with TERM; 137: it needed KILL as well.
  if [ "$CODE" -eq 124 ] || [ "$CODE" -eq 137 ]; then
    echo "--- $s log, last 40 lines:"
    tail -n 40 "$SLOG"
    echo "SMOKE: $s timed out after $SCRIPT_LIMIT_SEC s"
    FAILED=$((FAILED + 1))
  elif [ "$CODE" -ne 0 ] || grep -qE "SCRIPT ERROR|Parse Error" "$SLOG"; then
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

# Bot match (cards T09, T18): a headless server (45 s) and test bots 1-4 (25 s
# each, 1 s apart), one per hero, play on UDP 7777, the real network path.
# Passes when all five exit 0, no log has an error, the server logged at least
# one hit and an ability_used for each of the four abilities (T18), and nothing
# was refused ([Move], [Shot] or [Ability]). Anything still running after 60 s
# is killed by PID.
# Bot n plays hero n; each must use its ability (the roster's file names and ability names).
MATCH_HEROES=(bruiser mage scout medic)
MATCH_ABILITIES=("Shield Charge" "Blink" "Jet Dash" "Heal Drone")
NAMES=(server bot1 bot2 bot3 bot4)
LOGS=("$(mktemp)" "$(mktemp)" "$(mktemp)" "$(mktemp)" "$(mktemp)")
PIDS=()
stop_match_leftovers() {
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      # Git Bash: the console build starts a child, so kill the Windows tree too.
      if [ -r "/proc/$pid/winpid" ]; then taskkill //F //T //PID "$(cat "/proc/$pid/winpid")" >/dev/null 2>&1; fi
      kill -9 "$pid" 2>/dev/null
      echo "SMOKE: killed leftover process $pid"
    fi
  done
}
trap stop_match_leftovers EXIT
MATCH_START=$SECONDS
"$GODOT" --headless --path "$ROOT" -- --server --quit-after-sec=45 >"${LOGS[0]}" 2>&1 &
PIDS+=("$!")
STATE="timeout"
while [ $((SECONDS - MATCH_START)) -lt 30 ]; do
  if grep -q "could not host" "${LOGS[0]}"; then STATE="in use"; break; fi
  if grep -q "server up" "${LOGS[0]}"; then STATE="up"; break; fi
  if ! kill -0 "${PIDS[0]}" 2>/dev/null; then STATE="exited"; break; fi
  sleep 0.2
done
if [ "$STATE" = "in use" ]; then
  echo "SMOKE: FAIL: UDP 7777 is in use: stop the other server"
  exit 1
fi
if [ "$STATE" != "up" ]; then
  cat "${LOGS[0]}"
  echo "SMOKE: FAIL: the bot match server did not start ($STATE, log: ${LOGS[0]})"
  exit 1
fi
# 1 s apart, so they also leave 1 s apart. Two peers leaving in the same server
# frame make Godot's server relay log an ERROR: it tells the second about the
# first after ENet has already dropped it.
for n in 1 2 3 4; do
  if [ "$n" -gt 1 ]; then sleep 1; fi
  "$GODOT" --headless --path "$ROOT" -- --join=127.0.0.1 --bot=$n --hero=${MATCH_HEROES[$((n - 1))]} --quit-after-sec=25 >"${LOGS[$n]}" 2>&1 &
  PIDS+=("$!")
done
while [ $((SECONDS - MATCH_START)) -lt 60 ]; do
  RUNNING=0
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then RUNNING=$((RUNNING + 1)); fi
  done
  [ "$RUNNING" -eq 0 ] && break
  sleep 0.5
done
stop_match_leftovers
MATCH_FAILED=0
for i in 0 1 2 3 4; do
  wait "${PIDS[$i]}"
  CODE=$?
  if [ "$CODE" -ne 0 ]; then
    echo "SMOKE: bot match: ${NAMES[$i]} exited $CODE"
    MATCH_FAILED=1
  fi
done
PIDS=()
trap - EXIT
if grep -nE "SCRIPT ERROR|Parse Error|ERROR:" "${LOGS[@]}"; then MATCH_FAILED=1; fi
if grep -nE "\[(Move|Shot|Ability)\]" "${LOGS[@]}"; then MATCH_FAILED=1; fi
HITS=$(grep -c "\[Combat\] hero_damaged" "${LOGS[0]}")
ABILITIES=$(grep -c "\[Combat\] ability_used" "${LOGS[0]}")
if [ "$HITS" -eq 0 ]; then
  echo "SMOKE: bot match: the server logged no [Combat] hero_damaged"
  MATCH_FAILED=1
fi
for ability in "${MATCH_ABILITIES[@]}"; do
  if ! grep -qE "\[Combat\] ability_used: Player [0-9]+ used $ability," "${LOGS[0]}"; then
    echo "SMOKE: bot match: the server logged no ability_used for $ability"
    MATCH_FAILED=1
  fi
done
if [ "$MATCH_FAILED" -ne 0 ]; then
  # On GitHub nobody can open the temp files, so show the end of each log here.
  for i in 0 1 2 3 4; do
    echo "--- ${NAMES[$i]} log, last 40 lines:"
    tail -n 40 "${LOGS[$i]}"
  done
  echo "SMOKE: FAIL: bot match (logs: server ${LOGS[0]}, bot1-4 ${LOGS[1]} ${LOGS[2]} ${LOGS[3]} ${LOGS[4]})"
  exit 1
fi
echo "SMOKE: bot match passed (server and 4 bots exited 0, all four abilities used, $HITS hits, $ABILITIES abilities, $((SECONDS - MATCH_START)) s)"
echo "SMOKE: PASS"
