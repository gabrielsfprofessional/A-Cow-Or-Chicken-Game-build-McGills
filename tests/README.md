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

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".
