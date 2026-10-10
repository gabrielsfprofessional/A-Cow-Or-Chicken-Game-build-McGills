extends SceneTree
## Proves the arena check catches each kind of broken map. Owner: Adam (game/maps).
## Each case breaks a fresh copy of the arena in memory (never the file) and expects
## a problem containing the given words. The real arena must have no problems.
## Run from the repo folder:
##   godot --headless --path . --script res://game/maps/tools/test_arena_check.gd
## Exits with code 1 when any case is wrong.

const MAP_PATH: String = "res://game/maps/arena/arena_graybox.tscn"
const BLOCK_PATH: String = "res://game/maps/arena/block.tscn"

var _map_scene: PackedScene
var _block_scene: PackedScene
var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_map_scene = load(MAP_PATH) as PackedScene
	_block_scene = load(BLOCK_PATH) as PackedScene
	_expect("the real arena", _leave_alone, "")
	_expect("Cover05 48 px from the left wall", _crowd_wall, "48 px apart")
	_expect("Cover01 moved 10 px", _nudge_off_grid, "off the 48 px grid")
	_expect("SpawnA1 against the left wall", _crowd_spawn, "closer than 48 px")
	_expect("WallLeft too short", _open_wall, "hole")
	_expect("a block at the map root", _add_stray, "outside Walls and Cover")
	_expect("Cover07 shape moved", _move_shape, "does not match its Size")
	_expect("Cover07 scaled", _scale_block, "scaled or rotated")
	_expect("a sealed pocket under the top wall", _seal_pocket, "can't be reached")
	_expect("map size off the grid", _bad_map_size, "multiple of 48")
	_expect("SpawnA1 and SpawnB1 on a clear line", _open_sight, "SpawnA1 and SpawnB1 can see each other")
	_expect("a block 48 px from Cover07, corner to corner", _crowd_corner, "Cover/Cover07 and Cover/CornerBlock are 68 px apart")
	print("ARENA TEST: %s (%d cases)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


## Runs one case. Empty words means the map must have no problems at all.
func _expect(case_name: String, break_map: Callable, words: String) -> void:
	_count += 1
	var map: ArenaMap = _map_scene.instantiate() as ArenaMap
	root.add_child(map)
	break_map.call(map)
	var problems: PackedStringArray = map.find_problems()
	var ok: bool = problems.is_empty() if words.is_empty() else _has_words(problems, words)
	if ok:
		print("  ok   %s" % case_name)
	else:
		_failed += 1
		printerr("  FAIL %s: expected %s, got %s" % [case_name, "no problems" if words.is_empty() else "\"%s\"" % words, problems])
	map.free()


func _has_words(problems: PackedStringArray, words: String) -> bool:
	for message: String in problems:
		if message.contains(words):
			return true
	return false


func _block(map: ArenaMap, path: String) -> ArenaBlock:
	return map.get_node(path) as ArenaBlock


func _new_block(parent: Node, block_name: String, at: Vector2, block_size: Vector2) -> void:
	var block: ArenaBlock = _block_scene.instantiate() as ArenaBlock
	block.name = block_name
	block.position = at
	block.size = block_size
	parent.add_child(block)


func _leave_alone(_map: ArenaMap) -> void:
	pass


func _crowd_wall(map: ArenaMap) -> void:
	_block(map, "Cover/Cover05").position.x = 96.0


func _nudge_off_grid(map: ArenaMap) -> void:
	_block(map, "Cover/Cover01").position.x += 10.0


func _crowd_spawn(map: ArenaMap) -> void:
	(map.get_node("Spawns/SpawnA1") as Marker2D).position.x = 72.0


func _open_wall(map: ArenaMap) -> void:
	_block(map, "Walls/WallLeft").size = Vector2(48, 1968)


func _add_stray(map: ArenaMap) -> void:
	_new_block(map, "StrayBlock", Vector2(192, 480), Vector2(96, 96))


func _move_shape(map: ArenaMap) -> void:
	(map.get_node("Cover/Cover07/Shape") as CollisionShape2D).position = Vector2.ZERO


func _scale_block(map: ArenaMap) -> void:
	_block(map, "Cover/Cover07").scale = Vector2(2, 2)


func _seal_pocket(map: ArenaMap) -> void:
	var cover: Node = map.get_node("Cover")
	_new_block(cover, "PocketLeft", Vector2(1680, 48), Vector2(48, 288))
	_new_block(cover, "PocketRight", Vector2(2112, 48), Vector2(48, 288))


func _bad_map_size(map: ArenaMap) -> void:
	map.map_size = Vector2(3850, 2160)


## y = 264 runs above all cover, so nothing stands between the two spawns.
func _open_sight(map: ArenaMap) -> void:
	(map.get_node("Spawns/SpawnA1") as Marker2D).position.y = 264.0
	(map.get_node("Spawns/SpawnB1") as Marker2D).position.y = 264.0


## Cover07 ends at (1296, 816); this block starts 48 px right and 48 px down.
func _crowd_corner(map: ArenaMap) -> void:
	_new_block(map.get_node("Cover"), "CornerBlock", Vector2(1344, 864), Vector2(48, 48))
