extends SceneTree
## Checks a graybox map by script instead of by eye. Owner: Adam (game/maps).
## Runs the same check the arena shows as a yellow warning in the editor (ArenaMap.find_problems).
## Run from the repo folder:
##   godot --headless --path . --script res://game/maps/tools/check_arena.gd
## Optional: add -- res://path/to/other_map.tscn to check another map that uses ArenaMap.
## Exits with code 1 when the map has problems.

const DEFAULT_MAP: String = "res://game/maps/arena/arena_graybox.tscn"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var map_path: String = args[0] if args.size() > 0 else DEFAULT_MAP
	var scene: PackedScene = load(map_path) as PackedScene
	var map: ArenaMap = scene.instantiate() as ArenaMap if scene != null else null
	if map == null:
		_finish(map_path, PackedStringArray(["could not load %s as an ArenaMap" % map_path]))
		return
	root.add_child(map)
	_finish(map_path, map.find_problems())


func _finish(map_path: String, problems: PackedStringArray) -> void:
	print("Checking %s" % map_path)
	for message: String in problems:
		printerr("ARENA CHECK: %s" % message)
	print("ARENA CHECK: %s" % ("PASS" if problems.is_empty() else "FAIL (%d problems)" % problems.size()))
	quit(0 if problems.is_empty() else 1)
