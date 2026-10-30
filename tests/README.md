# tests

Owner: Gabe

Plain scripts until we need more: no GUT, no addons. Each test is a
`tests/<name>_test.gd` that extends `SceneTree`, prints one line per case and
exits 1 when any case fails.

Run one:

    C:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/move_check_test.gd

The smoke test (`tools/smoke.ps1`, `tools/smoke.sh`) runs every `tests/*_test.gd`
and fails on a non-zero exit, so GitHub runs them on every pull request. It also
runs Adam's `game/maps/tools/check_arena.gd` and every `test_*.gd` in
`game/maps/tools` and `game/modes/tools` (sorted by name) when they exist.

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
| `health_test.gd` | Health (T08): damage, floor at 0, eliminated exactly once, no damage while eliminated, respawn restores, client mirror, late-join sync; healing (T18): heals and returns the amount, only what fits under max, nothing at max, while eliminated or for 0 or less; `Health.heal()` emits once per heal and never for 0; a mirrored heal takes the server's health and does nothing while eliminated |
| `projectile_test.gd` | Server shots in a real physics world (T08): a 100 px/tick shot never tunnels, walls block, range expires, a hero stepping onto a shot or overlapping the shooter is hit, a shot starting in a wall never starts, the shooter is never hit, a disabled collider lets shots pass |
| `data_test.gd` | The hero and weapon data (T13): every `.tres` in `game/heroes/data` and `game/weapons/data` loads, is a known type, passes `validate()`, and the roster has no empty slot, the roster is bruiser, mage, scout, medic (the tools' order), `index_of()` gives -1 for an unknown name and `at()` null out of range (T18); `validate()` catches out-of-range numbers (at both ends, NaN, INF), empty texts, a missing weapon, a bad weapon passed on to its hero, an empty roster slot; `or_greater` / `or_less` are open-ended and other range flags don't change limits; a `.tres` with a wrong script path fails, naming the file; abilities (T14): `bruiser.tres` has `shield_charge.tres`, a charge at the defaults passes, a hero with no ability fails (T18), an empty name and each charge number out of range fail once each, `knockback_px` 0 passes, a dash or knockback over 4000 px/s fails (exactly 4000 passes), the speed cap stays within `RemoteTimeline.SNAP_DISTANCE`, a bad ability fails its hero; every ability file names a node script that exists (T18), and `make()` gives null for no script, a missing one or one that does not extend `Ability`; `scout.tres` has `jet_dash.tres` (2 charges, no knockback), `charges` 0 and 6 fail, 1 and 5 pass; `mage.tres` has `blink.tres`, a blink at the defaults passes, `distance_px` 47 and 481 fail, 48 and 480 pass; `medic.tres` has `heal_drone.tres`, a heal drone at the defaults passes (8 ticks, 40 HP), each of its numbers out of range fails once, `duration_sec` 4.2 with 0.5 s ticks fails, 4.5 passes |
| `bot_rules_test.gd` | A test bot's decisions (T09): the nearest visible hero wins; itself, eliminated, blocked and out-of-range heroes are ignored; no target holds fire; aim error within ±6°; 0.5-1.5 s bursts and 0.3-1 s pauses; a look every 0.25 s; a stuck bot re-picks after 1 s, steady progress keeps the point, arrival and the 4-8 s wander time re-pick; points stay in the area; the same seed makes the same choices; Q (T14): pressed only with a target and the ability ready, released when the target drops |
| `ability_check_test.gd` | The server's ability check (T14): wrong owner is dropped and books nothing; another life and eliminated are not logged refusals; zero/NaN/INF direction is refused; the direction is normalized; the cooldown refuses until exactly `cooldown_sec` and counts again from each use; the cooldown carries through death; an honest owner (countdown from the answer, 1-241 ms one way) is never refused over 20 uses; charges (T18): two at once then a refusal that books nothing, ready in 0 s while one is left, each charge back exactly `cooldown_sec` after its own use (refused 0.01 s before), `charge_ready_in` soonest first, charges kept through death, an honest owner with 2 charges never refused over 30 uses |
| `charge_sweep_test.gd` | The dash hit test in a real physics space (T14): a hero-sized circle swept 240 px finds a hero mid-path and one overlapping by 2 px, misses one 20 px beside or past the end, skips the excluded dasher and a hero with its collider off; a sweep that doesn't move checks only where it is. Fails itself after 10 s if an await hangs |
| `profile_store_test.gd` | The server's player saves (T21 part 1): `--saves` and the debug/release folders; ids are the token's SHA-256 (64 lowercase hex, no sign); a round trip keeps ints and capitals and never stores the token; every validation rule refuses and writes nothing; unknown fields are dropped, numbers past 2^53 and a name that wouldn't load back are refused; a crash while writing the `.tmp` or between the two renames loses only the newest save; a cut-short file falls back to `.bak` and is moved aside unchanged; two unreadable files are both kept; a newer save (main or `.bak`) is never touched; a file holding another id is moved aside; quick saves keep the settled `.bak` as `.old`, which loads after a pulled plug; a locked save is LOCKED, never a new player (as a user who can't open it; skipped on Windows and as root); `list_ids()` reads `.json`, `.json.bak` and `.json.old` only. The 20-kill crash test is `tools/save_crash_test.*` (not in smoke; see server/README.md) |

## The bot match (cards T09, T18)

After the tests, smoke plays a short match on the real network path, on UDP 7777:

1. It starts a headless server with `--quit-after-sec=45` and waits for
   `server up`. If the server can't host, smoke fails with
   `UDP 7777 is in use: stop the other server` and starts no bots, so they never
   join someone else's server.
2. It starts test bots 1-4, one per hero (`--join=127.0.0.1 --bot=<n>
   --hero=<bruiser, mage, scout, medic> --quit-after-sec=25`, T18), 1 s apart so
   they also leave 1 s apart (see game/net/README.md, "Load test").
3. It passes when all five exit 0, no log has `SCRIPT ERROR`, `Parse Error` or
   `ERROR:`, the server logged at least one `[Combat] hero_damaged` and an
   `[Combat] ability_used` for each of Shield Charge, Blink, Jet Dash and Heal
   Drone (T18), and no log has a `[Move]`, `[Shot]` or `[Ability]` line.

Anything still running after 60 s is killed by PID. The match adds about 46 s.
On Windows the logs are `%TEMP%\acoc-smoke-server.log`, `-bot1.log` to
`-bot4.log`, each with an `.err.log` for stderr; `smoke.sh` prints its temp file
paths when it fails. Running smoke while a server is up on this PC fails on
purpose: stop that server first.

## Check tools (T18 follow-up)

| Tool | What it does |
| --- | --- |
| `tools/smoke_repeat.ps1 [-Times 3]` | Runs smoke that many times in a row, prints each run's exit code and last `SMOKE:` line, then `SMOKE REPEAT: <passed>/<Times> passed`. Exit 0 only when every run passed; every run goes even after a failure. Logs: `%TEMP%\acoc-smoke-run<n>.log`. |
| `tools/hand_check.ps1 <step>` | A hand check on this PC: `start` (headless server and bots, each running Rounds x (RoundSec + GapSec) + 120 s, defaults 4 x (100 + 90) + 120 = 880 s), `open -Hero <name>` (the game window for one round, brought to the front), `mark` (the round starts), `finish` (waits out the round, closes the window by PID, prints the server's `[Combat]` lines for that player with counts), `stop` (everything by PID, then checks UDP 7777), `status`. Logs: `%TEMP%\acoc-hand`. Don't pipe `start` or `open`: the games inherit the pipe and hold it open until they exit. |
| `tools/focus_game.ps1 -GamePid <pid>` | Brings that process's game window (or its child's: the console build starts the game as one) to the front by minimizing and restoring it. Never looks windows up by title, never sends keys, never touches another window. Exit 0 when the window in front is that PID's, 1 when not, 2 when the PID isn't running. |

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".
