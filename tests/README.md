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

Each script gets 60 s. One still running then is killed (by PID in `smoke.ps1`,
by `timeout --kill-after=5s 60s` in `smoke.sh`), and smoke fails with
`<script> timed out after 60 s` and the last 40 lines of its log. A test that
awaits frames should still fail itself sooner, with a reason, as
`charge_sweep_test.gd` does after 10 s. On Windows each script's logs are
`%TEMP%\acoc-smoke-<name>.log` and `.err.log`.

| Test | What it covers |
| --- | --- |
| `move_check_test.gd` | The server's movement check (T07): wrong owner, old sequence, too far, time budget, huge sequence jump, NaN/INF, out of bounds, a player who lags as they join; `reset()` on respawn (T08); dash grants (T14): a dash step without a grant is too far, a 240 px grant lets a 4-send dash through and is drawn only for the excess over walking, walking never draws on it, a used-up or expired grant refuses the next step and never comes back, two grants add up and the later expiry wins, `reset()` clears it |
| `remote_timeline_test.gd` | Remote hero playback (T07): never backward, rate within 10%, extrapolate 100 ms then hold, snap, clock offset settling, no underruns at 150 ms lag + 50 ms jitter; `reset()` on respawn adds no underruns (T08) |
| `delay_queue_test.gd` | The `--sim-lag` / `--sim-jitter` queue (T07): never reorders, delays stay in range; carries each message's life (T08) |
| `shot_check_test.gd` | The server's fire check (T08): wrong owner, old shot id, dead shooter, earlier life, NaN/INF/zero direction, the rate schedule at both jitter boundaries, a late shot, a x2 stream, 60 s through 150 ms lag + 50 ms jitter |
| `health_test.gd` | Health (T08): damage, floor at 0, eliminated exactly once, no damage while eliminated, respawn restores, client mirror, late-join sync |
| `projectile_test.gd` | Server shots in a real physics world (T08): a 100 px/tick shot never tunnels, walls block, range expires, a hero stepping onto a shot or overlapping the shooter is hit, a shot starting in a wall never starts, the shooter is never hit, a disabled collider lets shots pass |
| `data_test.gd` | The hero and weapon data (T13): every `.tres` in `game/heroes/data` and `game/weapons/data` loads, is a known type, passes `validate()`, and the roster has no empty slot; `validate()` catches out-of-range numbers (at both ends, NaN, INF), empty texts, a missing weapon, a bad weapon passed on to its hero, an empty roster slot; `or_greater` / `or_less` are open-ended and other range flags don't change limits; a `.tres` with a wrong script path fails, naming the file; abilities (T14): `bruiser.tres` has `shield_charge.tres`, a charge at the defaults passes, a hero with no ability passes (until T18), an empty name and each charge number out of range fail once each, `knockback_px` 0 passes, a dash or knockback over 4000 px/s fails (exactly 4000 passes), the speed cap stays within `RemoteTimeline.SNAP_DISTANCE`, a bad ability fails its hero; every ability file names a node script that exists (T18) |
| `bot_rules_test.gd` | A test bot's decisions (T09): the nearest visible hero wins; itself, eliminated, blocked and out-of-range heroes are ignored; no target holds fire; aim error within ±6°; 0.5-1.5 s bursts and 0.3-1 s pauses; a look every 0.25 s; a stuck bot re-picks after 1 s, steady progress keeps the point, arrival and the 4-8 s wander time re-pick; points stay in the area; the same seed makes the same choices; Q (T14): pressed only with a target and the ability ready, released when the target drops |
| `ability_check_test.gd` | The server's ability check (T14): wrong owner is dropped and books nothing; another life and eliminated are not logged refusals; zero/NaN/INF direction is refused; the direction is normalized; the cooldown refuses until exactly `cooldown_sec` and counts again from each use; the cooldown carries through death; an honest owner (countdown from the answer, 1-241 ms one way) is never refused over 20 uses |
| `charge_sweep_test.gd` | The dash hit test in a real physics space (T14): a hero-sized circle swept 240 px finds a hero mid-path and one overlapping by 2 px, misses one 20 px beside or past the end, skips the excluded dasher and a hero with its collider off; a sweep that doesn't move checks only where it is. Fails itself after 10 s if an await hangs |

## The bot match (card T09)

After the tests, smoke plays a short match on the real network path, on UDP 7777:

1. It starts a headless server with `--quit-after-sec=40` and waits for
   `server up`. If the server can't host, smoke fails with
   `UDP 7777 is in use: stop the other server` and starts no bots, so they never
   join someone else's server.
2. It starts test bots 1 and 2 (`--join=127.0.0.1 --bot=<n> --quit-after-sec=25`),
   1 s apart so they also leave 1 s apart (see game/net/README.md, "Load test").
3. It passes when all three exit 0, no log has `SCRIPT ERROR`, `Parse Error` or
   `ERROR:`, the server logged at least one `[Combat] hero_damaged` and one
   `[Combat] ability_used` (T14), and no log has a `[Move]`, `[Shot]` or
   `[Ability]` line.

Anything still running after 60 s is killed by PID. The match adds about 40 s.
On Windows the logs are `%TEMP%\acoc-smoke-server.log`, `-bot1.log` and
`-bot2.log`, each with an `.err.log` for stderr; `smoke.sh` prints its temp file
paths when it fails. Running smoke while a server is up on this PC fails on
purpose: stop that server first.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".
