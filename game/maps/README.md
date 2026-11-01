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

Map check: open a map in Godot; a yellow warning next to its root node in the Scene panel means a problem.
Run from the repo folder (each exits with 1 on a problem):

- Check every map (the smoke test runs this): `godot --headless --path . --script res://game/maps/tools/check_arena.gd`.
  Every `.tscn` under `game/maps` must load and be a graybox map, apart from the map parts listed in
  `NOT_MAPS` in `check_arena.gd` (`block.tscn`, `fly_camera.tscn`), which it skips with a `Skipping <path>` line.
  A scene that doesn't load, or isn't a graybox map and isn't listed, fails and says what to do.
  When you add a new map part (a scene that isn't a map), add its path to `NOT_MAPS`.
- Check one map: `godot --headless --path . --script res://game/maps/tools/check_arena.gd -- res://game/maps/practice/practice_range.tscn`
- Test that the check catches broken maps: `godot --headless --path . --script res://game/maps/tools/test_arena_check.gd`
- Test that the check catches broken practice ranges: `godot --headless --path . --script res://game/maps/tools/test_practice_check.gd`
