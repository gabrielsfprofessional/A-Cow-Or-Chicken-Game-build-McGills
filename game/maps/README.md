# game/maps

Owner: Adam

Arena, Battle Royale and practice range maps. Cards: T05, T20, T23, T34, A01.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".

Maps:

- `arena/arena_graybox.tscn`: the Arena graybox (T05).
- `practice/practice_range.tscn`: the practice range graybox (T20): one PlayerSpawn and spots for target dummies.

Both share the general map rules in `graybox_map.gd` (48 px grid, closed outer wall, room between
blocks, no dead ends). Each map script adds its own: the arena needs 8 team spawns, 10-14 cover blocks
and no sight line between enemy spawns; the practice range needs exactly one PlayerSpawn and 1-8 dummy spots.

## How the arena looks (T34)

The arena is dressed by its `Dressing` node (`arena/arena_dressing.tscn`, script `ArenaDressing`), which sits
right after `Floor` and before `Walls`. It changes looks only: no block, spawn or map size moves, and it
holds no collision, spawn or navigation node. The practice range keeps the plain graybox look.

What it draws:

- Blue's floor on the left and Orange's on the right, each reaching 1296 px in from its side wall. The middle stays plain.
- A thin square frame, 144 px, on the floor around each spawn point, in its team's shade.
- The left wall in Blue and the right wall in Orange. The top and bottom walls are dark.
- Cover a lighter gray with a bright 4 px line just inside its edge.

Where the colors come from:

- The two team colors are read from `game/heroes/data/team_marks.tres` when the map starts: the same file the
  hero rings use (Gabe's; read, never edited here). No team color is typed into `game/maps`. If that file
  can't be read, the map prints one error, shows no team colors and still plays.
- Everything else is in `data/arena_look.tres` (`ArenaLookData`, script `arena_look_data.gd`). To change a
  value: double-click `arena_look.tres` in the FileSystem panel, change it in the Inspector, save, then
  close and reopen the arena scene to see it.

| Value in `arena_look.tres` | Now | What it does |
| --- | --- | --- |
| `side_width_px` | 1296 | How far each team's floor reaches in from its side wall |
| `side_darken` | 0.72 | How much darker than the team's color its floor shade is |
| `side_mix` | 0.6 | How much of that shade is mixed into the floor |
| `pad_size_px`, `pad_line_px` | 144, 6 | The frame around each spawn point |
| `pad_darken`, `pad_mix` | 0.62, 0.6 | The frame's shade, worked out like the floor's |
| `side_wall_darken` | 0.15 | How much darker than the team's color its side wall is |
| `wall_fill` | dark gray | The top and bottom walls |
| `cover_fill`, `cover_edge`, `cover_edge_px` | gray, near white, 4 | Cover and the line inside its edge |
| `min_contrast` | 3.0 | The least contrast kept (see below) |

The rule the values must keep (`ArenaLookData.sight_problems()`): cover, both team rings and a hero's name
(white) each stand out from every floor shade by `min_contrast` or more, and a name still reads over cover.
Contrast runs from 1 (the same) to 21 (black on white). A value that breaks the rule shows as a yellow
warning next to `Dressing` in the Scene panel, and fails `test_arena_look.gd`.

A block can be given a look by its map: `ArenaBlock.set_look(fill, edge, edge_px)`; `fill()` reads it back.
Without it a block keeps the plain gray.

## Map check

Map check: open a map in Godot; a yellow warning next to its root node in the Scene panel means a problem.
Run from the repo folder (each exits with 1 on a problem):

- Check every map (the smoke test runs this): `godot --headless --path . --script res://game/maps/tools/check_arena.gd`.
  Every `.tscn` under `game/maps` must load and be a graybox map, apart from the map parts listed in
  `NOT_MAPS` in `check_arena.gd` (`arena_dressing.tscn`, `block.tscn`, `fly_camera.tscn`), which it skips with a `Skipping <path>` line.
  A scene that doesn't load, or isn't a graybox map and isn't listed, fails and says what to do.
  When you add a new map part (a scene that isn't a map), add its path to `NOT_MAPS`.
- Check one map: `godot --headless --path . --script res://game/maps/tools/check_arena.gd -- res://game/maps/practice/practice_range.tscn`
- Test that the check catches broken maps: `godot --headless --path . --script res://game/maps/tools/test_arena_check.gd`
- Test that the check catches broken practice ranges: `godot --headless --path . --script res://game/maps/tools/test_practice_check.gd`
- Test the arena's look (T34: team colors from the rings' file, cover and rings stand out, looks only): `godot --headless --path . --script res://game/maps/tools/test_arena_look.gd`
