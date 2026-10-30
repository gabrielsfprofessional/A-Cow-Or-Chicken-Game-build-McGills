# game/heroes

Owner: Gabe

Hero scenes, abilities and hero data files (data/*.tres). Cards: T08, T13, T14, T18, A07.

`net_hero.tscn` / `net_hero.gd`: `NetHero`, the hero every player drives online
(T07-T09, T13; moved here from `game/net` in T14). It moves, sends, checks and
smooths, carries a Weapon and a Health, hides on elimination and respawns.
`setup()` gives it its HeroData. Its messages are in `game/net/README.md`.
`respawn_now()` (server) brings it back at once, alive or eliminated, for a
mode's new match (`world.respawn_all()`, see game/net/README.md, "New match").

T14 and T18, the Q abilities (messages in `game/net/README.md`):

| File | What it is |
| --- | --- |
| `ability.gd` | `Ability` (T18): what every Q ability shares, as the hero's `Ability` child, built by `NetHero.setup()` with `HeroData.ability.make()`. Asks the server on Q, starts its effect when it says yes, keeps each charge's countdown. A press while a request is out or forced motion runs is held and sent after, if a charge is ready. On the server: checks, runs the effect's grants, tells everyone. Each ability extends it and adds only its effect. |
| `dash.gd` | `Dash` (T14's ShieldCharge, renamed in T18): a dash toward the aim. On the server: grants, sweeps and knocks back (when `knockback_px` > 0); the dasher's respawn ends the sweep. |
| `blink.gd` | `Blink` (T18): a jump toward the aim in one physics tick, stopped short by a wall. On the server: grants the distance. Everyone else's copy snaps. |
| `heal_drone.gd` | `HealDrone` (T18): on the server, a heal tick every `tick_sec` through `duration_sec` for every alive hero within `radius_px` of the healer (the healer included), stopped by the healer's elimination or respawn. Every client draws the drone and its ring. |
| `ability_check.gd` | `AbilityCheck`: the server's pure check on each request (owner, life, alive, direction, a charge ready; T18: each charge comes back `cooldown_sec` after its own use). Tested by `tests/ability_check_test.gd`. |
| `charge_sweep.gd` | `ChargeSweep`: which heroes a dash stretch passes through. Tested against real physics by `tests/charge_sweep_test.gd`. |
| `spawn_protection.gd` | `SpawnProtection` (week-3 seams): the server's timer after a respawn, protected while now < its end. `NetHero.take_hit()` absorbs a shot and `knock_back()` does nothing while it runs; healing still works. Tested by `tests/match_rules_test.gd`. |

NetHero runs the forced motion itself (a dash, a blink or a knockback): whole physics
ticks, equal steps, stopped by walls, ended by a snap-back, elimination or respawn.

Who a Q touches comes from the world's `MatchRules` (`game/core/match_rules.gd`,
see game/net/README.md, "Seams for week 3"): Shield Charge knocks back enemies
only, the Heal Drone heals `can_heal()` heroes only (with no teams: everyone).

Kept on purpose (post-merge audit of T18, Gabe's call):
- **Blink passes through heroes** (#5). It is a teleport: only walls stop it,
  never a hero in the way, and it lands wherever the hero fits.
- **A Q press during a knockback is held** (#6), like one during your own dash:
  it goes out when the knockback ends, if a charge is ready. Revisit if any
  `knockback_duration_sec` goes above 0.3 s, where the wait starts to feel like a dropped key.

A protected hit still sends `receive_damage`, with **amount 0**, so every client
ends the shot on that hero. `Events.hero_damaged` fires with amount 0 too: T25's
damage numbers and hit sounds (John) should skip or soften amount 0.

T08: `health.tscn` (Health: put it under anything on physics layer 2 to make it
hittable) and `health_state.gd` (its rules). T18 adds healing: `heal()` on the
server, `show_heal()` on clients, never above max and never while eliminated.

Anything shootable must turn its collider off when its Health is eliminated
(NetHero does), or it stops shots like a wall. Health only emits signals, so
its parent does this. T20's dummies (Adam) need it too.

## Hero data (card T13)

Every hero number is in a `.tres` file you tune in the Inspector:

| File | What it is |
| --- | --- |
| `hero_data.gd` | `HeroData`: `display_name`, `role` (one line for hero select), `move_speed` (px/s), `max_health` (HP), `default_weapon` (a WeaponData from `game/weapons/data`). |
| `data/bruiser.tres`, `mage.tres`, `scout.tres`, `medic.tres` | The four heroes, named by role. Display names may change; the file names won't. |
| `hero_roster.gd`, `data/roster.tres` | `HeroRoster`: the heroes in hero-select order. Until T16's hero select, `--hero=<file name>` picks one (T18; `index_of()`, `at()`); the default is the first. |
| `ability_data.gd` | `AbilityData` (T14): what every Q ability has, `display_name`, `cooldown_sec` (s, per charge) and `charges` (1-5, T18), and `make()`, which builds its node from `node_script_path()` (T18). `make()` refuses, with an error, a path that is empty, missing, or not a script extending `ability.gd`, and `NetHero.setup()` reports a hero left without its Q. A hero's `ability` points at one, and is required (T18). |
| `dash_data.gd`, `data/shield_charge.tres`, `data/jet_dash.tres` | `DashData` (T14's ShieldChargeData, renamed in T18): the Bruiser's Q, and the Scout's (2 charges, 144 px in 0.15 s, no knockback): `cooldown_sec`, `dash_distance_px`, `dash_duration_sec`, `knockback_px`, `knockback_duration_sec`. A dash or knockback faster than 4000 px/s fails `validate()`. |
| `blink_data.gd`, `data/blink.tres` | `BlinkData` (T18): the Mage's Q, `cooldown_sec` 8 and `distance_px` (48-480 px, 240). No speed cap: remote copies snap on purpose. |
| `heal_drone_data.gd`, `data/heal_drone.tres` | `HealDroneData` (T18): the Medic's Q, `cooldown_sec` 14, `heal_per_tick_hp` 5, `tick_sec` 0.5, `duration_sec` 4 (a whole number of ticks), `radius_px` 144: 8 ticks, 40 HP. Everyone is an ally until T15. |
| `combat_data.gd`, `data/combat.tres` | `CombatData`: `respawn_sec` only, until T15's mode rules take it. |

- A hero's Health starts at its `max_health`. Health's own Inspector
  `max_health` (default 100) is for things that aren't heroes, such as T20's
  dummies.
- `validate()` on HeroData, HeroRoster, WeaponData and CombatData returns
  problems in plain words, for example `move_speed is 0 px/s; it must be 50 to
  1000 px/s`. The limits come from each field's own `@export_range`, so a
  number typed into the file by hand gets the same check as the Inspector.
  `or_greater` / `or_less` leave that end open (`it must be at least 1`); the
  `suffix:` is the unit in the message; `exp`, `degrees` and slider flags don't
  change the limits.
- `tests/data_test.gd` loads every `.tres` here and in `game/weapons/data`, and
  fails, naming the file and the problem, on a file that won't load, an unknown
  type (for example a wrong script path), any `validate()` problem or an empty
  roster slot. Smoke runs it.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".
