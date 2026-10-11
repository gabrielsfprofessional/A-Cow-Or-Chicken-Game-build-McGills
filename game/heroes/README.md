# game/heroes

Owner: Gabe

Hero scenes, abilities and hero data files (data/*.tres). Cards: T08, T13, T14, T18, A07.

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
| `combat_data.gd`, `data/combat.tres` | `CombatData`: `respawn_sec` only, until T15's mode rules take it. |
| `data_check.gd` | `DataCheck`: the shared range check behind every `validate()`. |

- A hero's Health starts at its `max_health`. Health's own Inspector
  `max_health` (default 100) is for things that aren't heroes, such as T20's
  dummies.
- `validate()` on HeroData, HeroRoster, WeaponData and CombatData returns
  problems in plain words, for example `move_speed is 0 px/s; it must be 50 to
  1000 px/s`. The limits come from each field's own `@export_range`, so a
  number typed into the file by hand gets the same check as the Inspector.
- `tests/data_test.gd` loads every `.tres` here and in `game/weapons/data`, and
  fails, naming the file and the problem, on a file that won't load, an unknown
  type, any `validate()` problem or an empty roster slot. Smoke runs it.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".
