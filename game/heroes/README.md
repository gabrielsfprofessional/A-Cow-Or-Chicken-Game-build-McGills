# game/heroes

Owner: Gabe

Hero scenes, abilities and hero data files (data/*.tres). Cards: T08, T13, T14, T18, A07.

`net_hero.tscn` / `net_hero.gd`: `NetHero`, the hero every player drives online
(T07-T09, T13; moved here from `game/net` in T14). It moves, sends, checks and
smooths, carries a Weapon and a Health, hides on elimination and respawns.
`setup()` gives it its HeroData. Its messages are in `game/net/README.md`.

T14 and T18, the Q abilities (messages in `game/net/README.md`):

| File | What it is |
| --- | --- |
| `ability.gd` | `Ability` (T18): what every Q ability shares, as the hero's `Ability` child, built by `NetHero.setup()` with `HeroData.ability.make()`. Asks the server on Q, starts its effect when it says yes, keeps the countdown. On the server: checks, runs the effect's grants, tells everyone. Each ability extends it and adds only its effect. |
| `dash.gd` | `Dash` (T14's ShieldCharge, renamed in T18): a dash toward the aim. On the server: grants, sweeps and knocks back (when `knockback_px` > 0). |
| `ability_check.gd` | `AbilityCheck`: the server's pure check on each request (owner, life, alive, direction, cooldown). Tested by `tests/ability_check_test.gd`. |
| `charge_sweep.gd` | `ChargeSweep`: which heroes a dash stretch passes through. Tested against real physics by `tests/charge_sweep_test.gd`. |

NetHero runs the forced motion itself (a dash or a knockback): whole physics
ticks, equal steps, stopped by walls, ended by a snap-back, elimination or respawn.

T08: `health.tscn` (Health: put it under anything on physics layer 2 to make it
hittable) and `health_state.gd` (its rules).

Anything shootable must turn its collider off when its Health is eliminated
(NetHero does), or it stops shots like a wall. Health only emits signals, so
its parent does this. T20's dummies (Adam) need it too.

## Hero data (card T13)

Every hero number is in a `.tres` file you tune in the Inspector:

| File | What it is |
| --- | --- |
| `hero_data.gd` | `HeroData`: `display_name`, `role` (one line for hero select), `move_speed` (px/s), `max_health` (HP), `default_weapon` (a WeaponData from `game/weapons/data`). |
| `data/bruiser.tres`, `mage.tres`, `scout.tres`, `medic.tres` | The four heroes, named by role. Display names may change; the file names won't. |
| `hero_roster.gd`, `data/roster.tres` | `HeroRoster`: the heroes in hero-select order. Everyone plays the first until T16's hero select. |
| `ability_data.gd` | `AbilityData` (T14): what every Q ability has, `display_name` and `cooldown_sec` (s), and `make()`, which builds its node (T18). A hero's `ability` points at one; empty means none (Mage, Scout and Medic until T18). |
| `dash_data.gd`, `data/shield_charge.tres` | `DashData` (T14's ShieldChargeData, renamed in T18), the Bruiser's Q: `cooldown_sec`, `dash_distance_px`, `dash_duration_sec`, `knockback_px`, `knockback_duration_sec`. A dash or knockback faster than 4000 px/s fails `validate()`. |
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
