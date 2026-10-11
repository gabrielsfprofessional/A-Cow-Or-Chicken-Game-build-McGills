# tests

Owner: Gabe

Plain scripts until we need more: no GUT, no addons. Each test is a
`tests/<name>_test.gd` that extends `SceneTree`, prints one line per case and
exits 1 when any case fails.

Run one:

    C:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/move_check_test.gd

The smoke test (`tools/smoke.ps1`, `tools/smoke.sh`) runs every `tests/*_test.gd`
and fails on a non-zero exit, so GitHub runs them on every pull request. It also
runs Adam's `game/maps/tools/check_arena.gd` and `test_arena_check.gd` when they
exist.

| Test | What it covers |
| --- | --- |
| `move_check_test.gd` | The server's movement check (T07): wrong owner, old sequence, too far, time budget, huge sequence jump, NaN/INF, out of bounds, a player who lags as they join; `reset()` on respawn (T08) |
| `remote_timeline_test.gd` | Remote hero playback (T07): never backward, rate within 10%, extrapolate 100 ms then hold, snap, clock offset settling, no underruns at 150 ms lag + 50 ms jitter; `reset()` on respawn adds no underruns (T08) |
| `delay_queue_test.gd` | The `--sim-lag` / `--sim-jitter` queue (T07): never reorders, delays stay in range; carries each message's life (T08) |
| `shot_check_test.gd` | The server's fire check (T08): wrong owner, old shot id, dead shooter, earlier life, NaN/INF/zero direction, the rate schedule at both jitter boundaries, a late shot, a x2 stream, 60 s through 150 ms lag + 50 ms jitter |
| `health_test.gd` | Health (T08): damage, floor at 0, eliminated exactly once, no damage while eliminated, respawn restores, client mirror, late-join sync |
| `projectile_test.gd` | Server shots in a real physics world (T08): a 100 px/tick shot never tunnels, walls block, range expires, a hero stepping onto a shot or overlapping the shooter is hit, a shot starting in a wall never starts, the shooter is never hit, a disabled collider lets shots pass |
| `bot_rules_test.gd` | A test bot's decisions (T09): the nearest visible hero wins; itself, eliminated, blocked and out-of-range heroes are ignored; no target holds fire; aim error within ±6°; 0.5-1.5 s bursts and 0.3-1 s pauses; a look every 0.25 s; a stuck bot re-picks after 1 s, steady progress keeps the point, arrival and the 4-8 s wander time re-pick; points stay in the area; the same seed makes the same choices |

## The bot match (card T09)

After the tests, smoke plays a short match on the real network path, on UDP 7777:

1. It starts a headless server with `--quit-after-sec=40` and waits for
   `server up`. If the server can't host, smoke fails with
   `UDP 7777 is in use: stop the other server` and starts no bots, so they never
   join someone else's server.
2. It starts test bots 1 and 2 (`--join=127.0.0.1 --bot=<n> --quit-after-sec=25`),
   1 s apart so they also leave 1 s apart (see game/net/README.md, "Load test").
3. It passes when all three exit 0, no log has `SCRIPT ERROR`, `Parse Error` or
   `ERROR:`, the server logged at least one `[Combat] hero_damaged`, and no log
   has a `[Move]` or `[Shot]` line.

Anything still running after 60 s is killed by PID. The match adds about 40 s.
On Windows the logs are `%TEMP%\acoc-smoke-server.log`, `-bot1.log` and
`-bot2.log`, each with an `.err.log` for stderr; `smoke.sh` prints its temp file
paths when it fails. Running smoke while a server is up on this PC fails on
purpose: stop that server first.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".
