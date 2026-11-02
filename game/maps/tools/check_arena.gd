extends SceneTree
## Checks graybox maps by script instead of by eye. Owner: Adam (game/maps).
## Runs the same check a map shows as a yellow warning in the editor (GrayboxMap.find_problems).
## Run from the repo folder:
##   godot --headless --path . --script res://game/maps/tools/check_arena.gd
## With no argument it checks every .tscn under game/maps (the smoke test runs it this way).
## Each one must load and be a graybox map, except the map parts in NOT_MAPS, which it skips.
## Optional: add -- res://path/to/one_map.tscn to check only that map, for example
##   -- res://game/maps/practice/practice_range.tscn
## Exits with code 1 when any scene fails, or when no graybox map is found.

const MAPS_FOLDER: String = "res://game/maps"
## Scenes under game/maps that are parts of maps, not maps. Every other .tscn there must be a graybox map.
const NOT_MAPS: PackedStringArray = [
	"res://game/maps/arena/block.tscn",
	"res://game/maps/arena/fly_camera.tscn",
]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var paths: PackedStringArray = args if args.size() > 0 else _find_scenes(MAPS_FOLDER)
	var checked: int = 0
	var failed: int = 0
	for map_path: String in paths:
		if args.is_empty() and NOT_MAPS.has(map_path):
			print("Skipping %s (a map part listed in NOT_MAPS)" % map_path)
			continue
		checked += 1
		if not _report(map_path, _check(map_path)):
			failed += 1
	if checked == 0:
		printerr("ARENA CHECK: no graybox map found under %s" % MAPS_FOLDER)
		quit(1)
		return
	var maps_word: String = "map" if checked == 1 else "maps"
	print("ARENA CHECK: %s" % ("PASS (%d %s)" % [checked, maps_word] if failed == 0 else "FAIL (%d of %d %s)" % [failed, checked, maps_word]))
	quit(0 if failed == 0 else 1)


## Every problem with the scene at map_path. A scene that won't load or isn't a graybox map is one problem.
func _check(map_path: String) -> PackedStringArray:
	var scene: PackedScene = load(map_path) as PackedScene if ResourceLoader.exists(map_path) else null
	if scene == null:
		return PackedStringArray(["%s did not load. Check the path is right, or open it in Godot and fix the red errors in the Output panel." % map_path])
	var node: Node = scene.instantiate()
	var map: GrayboxMap = node as GrayboxMap
	if map == null:
		if node != null:
			node.free()
		return PackedStringArray(["%s is not a graybox map. Give its root node a map script that extends GrayboxMap, or, if it is a part of maps, add it to NOT_MAPS in game/maps/tools/check_arena.gd." % map_path])
	root.add_child(map)
	var problems: PackedStringArray = map.find_problems()
	map.free()
	return problems


## Prints one scene's result. Returns true when it has no problems.
func _report(map_path: String, problems: PackedStringArray) -> bool:
	print("Checking %s" % map_path)
	for message: String in problems:
		printerr("ARENA CHECK: %s" % message)
	var problems_word: String = "problem" if problems.size() == 1 else "problems"
	print("ARENA CHECK: %s %s" % [map_path.get_file(), "PASS" if problems.is_empty() else "FAIL (%d %s)" % [problems.size(), problems_word]])
	return problems.is_empty()


## Every .tscn under folder, sorted, so the output reads the same each run.
func _find_scenes(folder: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for file: String in ResourceLoader.list_directory(folder):
		if file.ends_with("/"):
			found.append_array(_find_scenes(folder.path_join(file.trim_suffix("/"))))
		elif file.get_extension() == "tscn":
			found.append(folder.path_join(file))
	found.sort()
	return found
