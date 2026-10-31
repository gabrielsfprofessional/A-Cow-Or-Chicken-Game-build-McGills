# game/modes

Owner: Adam

Mode rules: teams, score limit, timer, zone, loot tables. Cards: T12, T15, A02, A05.

## What is here

| File | What it does |
| --- | --- |
| `arena_rules.gd` | `ArenaRules` (T12), server only: `MapRules` plus a smarter spawn pick and spawn protection. The arena map's `make_rules()` installs it, so `--map=arena` uses it. T15's mode extends it with teams. |
| `spawn_picker.gd` | `SpawnPicker.pick()`, the pick as pure math: among the points the hero's team may use, the one farthest from the nearest living enemy; ties go to the one farthest from the nearest living teammate, then to MapRules' own stable pick. Straight-line distance. |
| `arena_rules_data.gd`, `data/arena_rules.tres` | `spawn_protection_sec` (2 s). The respawn delay stays `combat.tres` `respawn_sec` (4 s). |
| `tools/test_arena_rules.gd` | Headless test; the smoke test runs every `test_*.gd` in `tools/`. |

T12 calls: the first spawn of a match gets no protection, and firing does not end it.
A mode with teams must override `is_enemy()` as well as `team_of()`: the pick keeps away from enemies only.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".
