extends SceneTree
## Proves the practice range check catches each kind of broken room. Owner: Adam (game/maps).
## Each case breaks a fresh copy of the room in memory (never the file) and expects
## a problem containing the given words. The real room must have no problems, even though
## it has only 4 cover blocks and no team spawns: the arena-only rules don't apply here.
## Run from the repo folder:
##   godot --headless --path . --script res://game/maps/tools/test_practice_check.gd
## Exits with code 1 when any case is wrong.

const MAP_PATH: String = "res://game/maps/practice/practice_range.tscn"
const BLOCK_PATH: String = "res://game/maps/arena/block.tscn"

var _map_scene: PackedScene
var _block_scene: PackedScene
var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_map_scene = load(MAP_PATH) as PackedScene
	_block_scene = load(BLOCK_PATH) as PackedScene
	_expect("the real practice range", _leave_alone, "")
	_expect("no player spawn", _remove_spawn, "Spawns/PlayerSpawn (a Marker2D) is missing")
	_expect("a second spawn", _add_spawn, "needs exactly 1, named PlayerSpawn")
	_expect("no dummy spots", _remove_dummies, "There are 0 dummy spots")
	_expect("a dummy spot that is not a Marker2D", _add_wrong_spot, "Dummies/Box is not a Marker2D")
	_expect("Dummy4 against the right wall", _crowd_dummy, "Dummies/Dummy4 is closer than 48 px to Walls/WallRight")
	_expect("Dummy2 48 px from Dummy1", _stack_dummies, "Dummies/Dummy1 and Dummies/Dummy2 are 48 px apart")
	_expect("DummyBehindWall boxed in", _box_dummy, "Dummies/DummyBehindWall can't be reached from PlayerSpawn")
	_expect("WallRight too short", _open_wall, "hole")
	_expect("Cover01 moved 10 px", _nudge_off_grid, "off the 48 px grid")
	print("PRACTICE TEST: %s (%d cases)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


## Runs one case. Empty words means the room must have no problems at all.
func _expect(case_name: String, break_map: Callable, words: String) -> void:
	_count += 1
	var map: PracticeRange = _map_scene.instantiate() as PracticeRange
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


func _marker(map: PracticeRange, path: String) -> Marker2D:
	return map.get_node(path) as Marker2D


func _new_block(parent: Node, block_name: String, at: Vector2, block_size: Vector2) -> void:
	var block: ArenaBlock = _block_scene.instantiate() as ArenaBlock
	block.name = block_name
	block.position = at
	block.size = block_size
	parent.add_child(block)


## Removes and frees a node at once, so find_problems no longer sees it.
func _delete(node: Node) -> void:
	node.get_parent().remove_child(node)
	node.free()


func _leave_alone(_map: PracticeRange) -> void:
	pass


func _remove_spawn(map: PracticeRange) -> void:
	_delete(map.get_node("Spawns/PlayerSpawn"))


func _add_spawn(map: PracticeRange) -> void:
	var extra: Marker2D = Marker2D.new()
	extra.name = "SecondSpawn"
	extra.position = Vector2(264, 1200)
	map.get_node("Spawns").add_child(extra)


func _remove_dummies(map: PracticeRange) -> void:
	for spot: Node in map.get_node("Dummies").get_children():
		_delete(spot)


func _add_wrong_spot(map: PracticeRange) -> void:
	var box: Node2D = Node2D.new()
	box.name = "Box"
	map.get_node("Dummies").add_child(box)


## WallRight starts at x = 2832, so x = 2808 is 24 px from it.
func _crowd_dummy(map: PracticeRange) -> void:
	_marker(map, "Dummies/Dummy4").position.x = 2808.0


func _stack_dummies(map: PracticeRange) -> void:
	_marker(map, "Dummies/Dummy2").position = _marker(map, "Dummies/Dummy1").position + Vector2(48, 0)


## LowWall is the left side of the box; three more blocks close it around DummyBehindWall at (1704, 1344).
func _box_dummy(map: PracticeRange) -> void:
	var cover: Node = map.get_node("Cover")
	_new_block(cover, "BoxTop", Vector2(1632, 1248), Vector2(192, 48))
	_new_block(cover, "BoxBottom", Vector2(1632, 1392), Vector2(192, 48))
	_new_block(cover, "BoxRight", Vector2(1776, 1296), Vector2(48, 96))


func _open_wall(map: PracticeRange) -> void:
	(map.get_node("Walls/WallRight") as ArenaBlock).size = Vector2(48, 1440)


func _nudge_off_grid(map: PracticeRange) -> void:
	(map.get_node("Cover/Cover01") as ArenaBlock).position.x += 10.0
