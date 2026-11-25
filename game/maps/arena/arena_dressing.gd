@tool
class_name ArenaDressing
extends Node2D
## The arena's dressing (T34): how the map looks, and nothing a hero touches. Owner: Adam (game/maps).
## A child of the map, right after Floor and before Walls, so it draws on the floor and under
## every block and hero. It paints each team's side of the floor and a frame around each
## spawn point, and gives the side walls, the other walls and the cover their colors.
## - The two team colors come from the hero rings' file (game/heroes/data/team_marks.tres),
##   read when the map starts, so a side always matches its team's rings.
## - Every other number and color is in game/maps/data/arena_look.tres (ArenaLookData).
## - It holds no collision, spawn or navigation node and keeps z_index 0: a negative
##   z_index would sort things under the floor.
## In the editor a yellow warning next to this node says what would be hard to see.

const LOOK_PATH: String = "res://game/maps/data/arena_look.tres"
## Where the game defines the two team colors: the file the hero rings are drawn from.
const TEAM_MARKS_PATH: String = "res://game/heroes/data/team_marks.tres"
const FLOOR_NODE: NodePath = ^"Floor"
const WALLS_NODE: NodePath = ^"Walls"
const COVER_NODE: NodePath = ^"Cover"

var _look: ArenaLookData = null
## [Blue, Orange], or empty when the team colors could not be read.
var _teams: Array[Color] = []
var _floor: Color = Color.BLACK
var _has_floor: bool = false


func _ready() -> void:
	refresh()


## Reads the look and the team colors again, then repaints the floor and recolors the blocks.
## A missing file is reported once here and leaves that part of the map plain.
func refresh() -> void:
	_look = load_look()
	_teams = team_colors()
	var floor_rect: ColorRect = get_parent().get_node_or_null(FLOOR_NODE) as ColorRect if get_parent() != null else null
	_has_floor = floor_rect != null
	_floor = floor_rect.color if floor_rect != null else Color.BLACK
	if not _has_floor:
		push_error("ArenaDressing: the map has no Floor (a ColorRect), so the team sides are not painted.")
	_dress_blocks()
	queue_redraw()
	if Engine.is_editor_hint():
		update_configuration_warnings()


## The look file, or null (with one error) when it is missing or not an ArenaLookData.
static func load_look() -> ArenaLookData:
	var look: ArenaLookData = load(LOOK_PATH) as ArenaLookData if ResourceLoader.exists(LOOK_PATH) else null
	if look == null:
		push_error("ArenaDressing: %s is missing or not an ArenaLookData, so the arena keeps its plain look." % LOOK_PATH)
	return look


## The two team colors, [Blue, Orange], from the hero rings' file. Empty (with one error)
## when that file can't be read: the map then shows no team colors, and still plays.
static func team_colors() -> Array[Color]:
	var marks: TeamMarkData = load(TEAM_MARKS_PATH) as TeamMarkData if ResourceLoader.exists(TEAM_MARKS_PATH) else null
	if marks == null:
		push_error("ArenaDressing: %s is missing or not a TeamMarkData, so the arena shows no team colors." % TEAM_MARKS_PATH)
		return []
	return colors_from(marks)


## [team 0's ring color, team 1's ring color] from `marks`.
static func colors_from(marks: TeamMarkData) -> Array[Color]:
	return [marks.ring_color(0), marks.ring_color(1)]


## The floor color on `team`'s side (0 left, 1 right) as drawn now; the plain floor when
## the look or the team colors are missing.
func side_color(team: int) -> Color:
	if _look == null or team < 0 or team >= _teams.size():
		return _floor
	return _look.side_floor(_floor, _teams[team])


## What would be hard to see with the look file's values, in plain words. Empty when fine.
func sight_problems() -> PackedStringArray:
	if _look == null or not _has_floor:
		return PackedStringArray()
	var problems: PackedStringArray = _look.validate()
	problems.append_array(_look.sight_problems(_floor, _teams))
	return problems


func _get_configuration_warnings() -> PackedStringArray:
	return sight_problems()


func _draw() -> void:
	if _look == null or not _has_floor or _teams.size() != 2:
		return
	var map_size: Vector2 = _map_size()
	var wall: float = ArenaBlock.GRID
	var side: float = clampf(_look.side_width_px, 0.0, map_size.x / 2.0 - wall)
	var height: float = map_size.y - 2.0 * wall
	if side > 0.0 and height > 0.0:
		draw_rect(Rect2(wall, wall, side, height), _look.side_floor(_floor, _teams[0]))
		draw_rect(Rect2(map_size.x - wall - side, wall, side, height), _look.side_floor(_floor, _teams[1]))
	var spawns: Node = get_parent().get_node_or_null(MapList.SPAWNS_NODE)
	if spawns == null:
		return
	for child: Node in spawns.get_children():
		var marker: Marker2D = child as Marker2D
		var team: int = MapList.team_of_spawn(String(child.name))
		if marker == null or team < 0 or team >= _teams.size():
			continue
		var corner: Vector2 = to_local(marker.global_position) - Vector2.ONE * _look.pad_size_px / 2.0
		draw_rect(Rect2(corner, Vector2.ONE * _look.pad_size_px), _look.pad_color(_floor, _teams[team]), false, _look.pad_line_px)


## Colors the blocks: a side wall in its team's color, the other walls dark, cover lighter
## with a bright edge. Drawing only: no block is moved or resized.
func _dress_blocks() -> void:
	if _look == null or get_parent() == null:
		return
	var map_size: Vector2 = _map_size()
	var walls: Node = get_parent().get_node_or_null(WALLS_NODE)
	if walls != null:
		for child: Node in walls.get_children():
			var block: ArenaBlock = child as ArenaBlock
			if block == null:
				continue
			var team: int = _side_of(block, map_size)
			var fill: Color = _look.side_wall(_teams[team]) if team >= 0 and team < _teams.size() else _look.wall_fill
			block.set_look(fill, fill, 0.0)
	var cover: Node = get_parent().get_node_or_null(COVER_NODE)
	if cover != null:
		for child: Node in cover.get_children():
			var block: ArenaBlock = child as ArenaBlock
			if block != null:
				block.set_look(_look.cover_fill, _look.cover_edge, _look.cover_edge_px)


## 0 when `block` lies wholly in the left wall's column, 1 in the right wall's, else -1.
func _side_of(block: ArenaBlock, map_size: Vector2) -> int:
	var left: float = to_local(block.global_position).x
	if left + block.size.x <= ArenaBlock.GRID:
		return 0
	if left >= map_size.x - ArenaBlock.GRID:
		return 1
	return -1


## The map's size from its root; zero when the root has none.
func _map_size() -> Vector2:
	var value: Variant = get_parent().get(&"map_size") if get_parent() != null else null
	return value if value is Vector2 else Vector2.ZERO
