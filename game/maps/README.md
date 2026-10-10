# game/maps

Owner: Adam

Arena, Battle Royale and practice range maps. Cards: T05, T20, T23, T34, A01.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".

Map check: open the arena in Godot; a yellow warning next to ArenaGraybox in the Scene panel means a problem.
Run from the repo folder (each exits with 1 on a problem):

- Check the arena: `godot --headless --path . --script res://game/maps/tools/check_arena.gd`
- Test that the check catches broken maps: `godot --headless --path . --script res://game/maps/tools/test_arena_check.gd`
