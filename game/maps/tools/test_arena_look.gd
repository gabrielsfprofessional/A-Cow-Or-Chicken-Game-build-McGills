extends SceneTree
## Proves the arena's dressing (T34) keeps its rules. Owner: Adam (game/maps).
## a. The team sides take their colors from the hero rings' file, never from a typed-in color.
## b. Cover stands out from every floor shade.
## c. Nothing hides a hero, a ring or a name: rings and names stand out from every floor shade,
##    a name still reads over cover, and the dressing draws on the floor, under everything else.
## d. The dressing is looks only: it holds no collision, spawn or navigation node.
## e. The look file's numbers are in range, and a bad value is caught.
## Run from the repo folder:
##   godot --headless --path . --script res://game/maps/tools/test_arena_look.gd
## Exits with code 1 when any case is wrong.

const MAP_PATH: String = "res://game/maps/arena/arena_graybox.tscn"
const PRACTICE_PATH: String = "res://game/maps/practice/practice_range.tscn"
const DRESSING_NODE: NodePath = ^"Dressing"

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	var look: ArenaLookData = ArenaDressing.load_look()
	var marks: TeamMarkData = load(ArenaDressing.TEAM_MARKS_PATH) as TeamMarkData
	var map: ArenaMap = _arena()
	# A node added here gets its _ready() once the tree starts, so the checks wait one frame:
	# they then see the map as _ready() dressed it, the way a match does.
	await process_frame
	var dressing: ArenaDressing = map.get_node_or_null(DRESSING_NODE) as ArenaDressing if map != null else null
	_expect(look != null and marks != null and dressing != null, "the look file, the hero rings' file and the arena's Dressing node are there",
		"look %s, rings %s, Dressing %s" % [look != null, marks != null, dressing != null])
	if look != null and marks != null and dressing != null:
		var teams: Array[Color] = ArenaDressing.team_colors()
		var floor_color: Color = (map.get_node(ArenaDressing.FLOOR_NODE) as ColorRect).color
		_test_team_colors(map, dressing, look, marks, teams, floor_color)
		await _test_cover(map, look, teams, floor_color)
		_test_nothing_hidden(map, dressing, look, teams, floor_color)
		_test_looks_only(dressing)
		_test_look_file(look, teams, floor_color)
	if map != null:
		map.free()
	print("ARENA LOOK TEST: %s (%d cases)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


## a. The colors on the map are the ring file's, and follow a ring file with other colors.
func _test_team_colors(map: ArenaMap, dressing: ArenaDressing, look: ArenaLookData, marks: TeamMarkData, teams: Array[Color], floor_color: Color) -> void:
	_expect(teams.size() == 2 and teams[0].is_equal_approx(marks.blue) and teams[1].is_equal_approx(marks.orange),
		"a. the two team colors are the hero rings' (team_marks.tres)", "got %s, the rings are %s and %s" % [teams, marks.blue, marks.orange])
	var other: TeamMarkData = TeamMarkData.new()
	other.blue = Color(0.1, 0.8, 0.2, 1)
	other.orange = Color(0.7, 0.2, 0.9, 1)
	var followed: Array[Color] = ArenaDressing.colors_from(other)
	_expect(followed.size() == 2 and followed[0].is_equal_approx(other.blue) and followed[1].is_equal_approx(other.orange),
		"a. a ring file with other colors changes the map's team colors", "got %s for %s and %s" % [followed, other.blue, other.orange])
	if teams.size() != 2:
		return
	_expect(dressing.side_color(0).is_equal_approx(look.side_floor(floor_color, marks.blue))
		and dressing.side_color(1).is_equal_approx(look.side_floor(floor_color, marks.orange))
		and not dressing.side_color(0).is_equal_approx(dressing.side_color(1)),
		"a. the left floor is Blue's shade and the right floor Orange's", "left %s, right %s" % [dressing.side_color(0), dressing.side_color(1)])
	var left: ArenaBlock = map.get_node_or_null(^"Walls/WallLeft") as ArenaBlock
	var right: ArenaBlock = map.get_node_or_null(^"Walls/WallRight") as ArenaBlock
	_expect(left != null and right != null and left.fill().is_equal_approx(look.side_wall(marks.blue)) and right.fill().is_equal_approx(look.side_wall(marks.orange)),
		"a. the left wall is Blue's and the right wall Orange's", "left %s, right %s" % [left.fill() if left != null else "missing", right.fill() if right != null else "missing"])


## b. Every cover block has the cover look, and it stands out from each floor shade.
func _test_cover(map: ArenaMap, look: ArenaLookData, teams: Array[Color], floor_color: Color) -> void:
	var dressed: int = 0
	var blocks: int = 0
	for child: Node in map.get_node(ArenaDressing.COVER_NODE).get_children():
		blocks += 1
		if child is ArenaBlock and (child as ArenaBlock).fill().is_equal_approx(look.cover_fill):
			dressed += 1
	_expect(blocks > 0 and dressed == blocks, "b. every cover block has the cover color", "%d of %d" % [dressed, blocks])
	var shades: Dictionary[String, Color] = look.floor_shades(floor_color, teams)
	var lowest: float = 21.0
	var lowest_name: String = ""
	for shade_name: String in shades:
		var found: float = ArenaLookData.contrast(look.cover_fill, shades[shade_name])
		if found < lowest:
			lowest = found
			lowest_name = shade_name
	_expect(shades.size() == 5 and lowest >= look.min_contrast, "b. cover stands out from all %d floor shades (lowest %.2f, on %s; needs %.1f)" % [shades.size(), lowest, lowest_name, look.min_contrast],
		"lowest contrast %.2f on %s" % [lowest, lowest_name])
	var practice: Node = (load(PRACTICE_PATH) as PackedScene).instantiate()
	_drop_cameras(practice)
	root.add_child(practice)
	await process_frame
	var plain: int = 0
	var practice_blocks: Array[Node] = practice.find_children("*", "StaticBody2D", true, false)
	for node: Node in practice_blocks:
		if node is ArenaBlock and (node as ArenaBlock).fill().is_equal_approx(ArenaBlock.COLOR):
			plain += 1
	_expect(practice_blocks.size() > 0 and plain == practice_blocks.size(), "b. the practice range's blocks keep their plain look", "%d of %d" % [plain, practice_blocks.size()])
	practice.free()


## c. Rings and names stand out everywhere, and the dressing draws on the floor, under the rest.
func _test_nothing_hidden(map: ArenaMap, dressing: ArenaDressing, look: ArenaLookData, teams: Array[Color], floor_color: Color) -> void:
	var problems: PackedStringArray = look.sight_problems(floor_color, teams)
	_expect(problems.is_empty(), "c. cover, both rings and names stand out with the look file's values", str(problems))
	_expect(dressing.sight_problems().is_empty(), "c. the Dressing node itself reports nothing hard to see", str(dressing.sight_problems()))
	var strong: ArenaLookData = look.duplicate() as ArenaLookData
	strong.side_darken = 0.0
	strong.side_mix = 0.9
	_expect(_has_words(strong.sight_problems(floor_color, teams), "Blue's ring is hard to see on Blue's side of the floor"),
		"c. a floor almost the team's own color is caught (it would hide the ring)", str(strong.sight_problems(floor_color, teams)))
	var pale: ArenaLookData = look.duplicate() as ArenaLookData
	pale.cover_fill = Color(0.9, 0.9, 0.9, 1)
	_expect(_has_words(pale.sight_problems(floor_color, teams), "a hero's name is hard to see on cover"),
		"c. cover pale enough to hide a name is caught", str(pale.sight_problems(floor_color, teams)))
	var floor_index: int = map.get_node(ArenaDressing.FLOOR_NODE).get_index()
	var walls_index: int = map.get_node(ArenaDressing.WALLS_NODE).get_index()
	_expect(dressing.get_parent() == map and dressing.get_index() == floor_index + 1 and dressing.get_index() < walls_index,
		"c. Dressing sits right after Floor and before Walls, so it draws under every block and hero",
		"Floor %d, Dressing %d, Walls %d" % [floor_index, dressing.get_index(), walls_index])
	var lowered: PackedStringArray = []
	var seen: int = 0
	for node: Node in map.find_children("*", "CanvasItem", true, false):
		seen += 1
		if (node as CanvasItem).z_index < 0:
			lowered.append(str(map.get_path_to(node)))
	_expect(seen > 0 and lowered.is_empty() and dressing.z_index == 0 and dressing.z_as_relative,
		"c. nothing on the map has a negative z_index (%d nodes read)" % seen, "negative: %s" % str(lowered))


## d. Looks only: nothing under the dressing can be touched, spawned on or walked by.
func _test_looks_only(dressing: ArenaDressing) -> void:
	var nodes: Array[Node] = [dressing]
	nodes.append_array(dressing.find_children("*", "", true, false))
	var touchable: PackedStringArray = []
	for node: Node in nodes:
		if node is CollisionObject2D or node is CollisionShape2D or node is CollisionPolygon2D or node is Marker2D or node.get_class().begins_with("Navigation"):
			touchable.append("%s (%s)" % [dressing.get_path_to(node), node.get_class()])
	_expect(touchable.is_empty(), "d. Dressing holds no collision, spawn or navigation node (%d nodes read)" % nodes.size(), str(touchable))


## e. The look file passes its own check, and each kind of bad value is caught.
func _test_look_file(look: ArenaLookData, teams: Array[Color], floor_color: Color) -> void:
	_expect(look.validate().is_empty(), "e. arena_look.tres passes validate()", str(look.validate()))
	var wide: ArenaLookData = look.duplicate() as ArenaLookData
	wide.side_mix = 2.0
	_expect(_has_words(wide.validate(), "side_mix"), "e. a number out of its range is caught", str(wide.validate()))
	var glass: ArenaLookData = look.duplicate() as ArenaLookData
	glass.cover_fill = Color(0.47, 0.5, 0.55, 0.5)
	_expect(_has_words(glass.validate(), "cover_fill is see-through"), "e. a see-through color is caught", str(glass.validate()))
	var hidden: ArenaLookData = look.duplicate() as ArenaLookData
	hidden.cover_fill = floor_color
	_expect(_has_words(hidden.sight_problems(floor_color, teams), "cover is hard to see on the plain floor"),
		"e. cover the color of the floor is caught", str(hidden.sight_problems(floor_color, teams)))
	var one_team: Array[Color] = [Color.RED]
	_expect(_has_words(look.sight_problems(floor_color, one_team), "needs the 2 team colors"),
		"e. a missing team color is caught", str(look.sight_problems(floor_color, one_team)))
	_expect(is_equal_approx(ArenaLookData.contrast(Color.BLACK, Color.WHITE), 21.0) and is_equal_approx(ArenaLookData.contrast(Color.RED, Color.RED), 1.0),
		"e. contrast is 21 for black on white and 1 for a color on itself",
		"%.2f and %.2f" % [ArenaLookData.contrast(Color.BLACK, Color.WHITE), ArenaLookData.contrast(Color.RED, Color.RED)])


## The arena in the tree, as the world builds it: without its offline-only cameras.
func _arena() -> ArenaMap:
	var scene: PackedScene = load(MAP_PATH) as PackedScene
	var map: ArenaMap = scene.instantiate() as ArenaMap if scene != null else null
	if map == null:
		return null
	_drop_cameras(map)
	root.add_child(map)
	return map


func _drop_cameras(map: Node) -> void:
	for camera: Node in map.find_children("*", "Camera2D", true, false):
		camera.get_parent().remove_child(camera)
		camera.free()


func _expect(ok: bool, case_name: String, detail: String) -> void:
	_count += 1
	if ok:
		print("  ok   %s" % case_name)
	else:
		_failed += 1
		printerr("  FAIL %s: %s" % [case_name, detail])


func _has_words(problems: PackedStringArray, words: String) -> bool:
	for message: String in problems:
		if message.contains(words):
			return true
	return false
