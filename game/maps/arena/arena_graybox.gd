@tool
class_name ArenaMap
extends GrayboxMap
## Graybox arena: Floor, Walls, Cover, Spawns, FlyCamera. Owner: Adam (game/maps).
## The shared map rules live in GrayboxMap; this adds the arena-only ones:
## 10-14 cover blocks, 8 team spawns on the right sides and no sight line between enemy spawns.

const MIN_COVER: int = 10
const MAX_COVER: int = 14
const SPAWN_NAMES: Array[String] = ["SpawnA1", "SpawnA2", "SpawnA3", "SpawnA4", "SpawnB1", "SpawnB2", "SpawnB3", "SpawnB4"]
## Team colors from PROJECT_PLAN (decided Oct 9): Blue and Orange.
const TEAM_A_COLOR: Color = Color("#3B82F6")
const TEAM_B_COLOR: Color = Color("#F97316")


func _check_layout(blocks: Array[ArenaBlock], cover: Array[ArenaBlock], problems: PackedStringArray) -> Dictionary:
	if cover.size() < MIN_COVER or cover.size() > MAX_COVER:
		problems.append("There are %d cover blocks; the arena needs %d-%d." % [cover.size(), MIN_COVER, MAX_COVER])
	var spawns: Dictionary = _check_spawns(blocks, problems)
	_check_sight(blocks, spawns, problems)
	return spawns


func _walk_start() -> String:
	return "SpawnA1"


func _marker_groups() -> Array[String]:
	return ["Spawns"]


func _marker_color(marker: Marker2D) -> Color:
	return TEAM_A_COLOR if marker.name.begins_with("SpawnA") else TEAM_B_COLOR


## Returns spawn name -> position for every spawn inside the walls.
func _check_spawns(blocks: Array[ArenaBlock], problems: PackedStringArray) -> Dictionary:
	var points: Dictionary = {}
	var group: Node = get_node_or_null(^"Spawns")
	if group == null:
		problems.append("There is no Spawns node.")
		return points
	if group.get_child_count() != SPAWN_NAMES.size():
		problems.append("Spawns has %d children; it needs exactly %d." % [group.get_child_count(), SPAWN_NAMES.size()])
	for spawn_name: String in SPAWN_NAMES:
		var marker: Marker2D = group.get_node_or_null(spawn_name) as Marker2D
		if marker == null:
			problems.append("Spawns/%s (a Marker2D) is missing." % spawn_name)
			continue
		_check_marker(spawn_name, marker, blocks, points, problems)
		if not points.has(spawn_name):
			continue
		var point: Vector2 = points[spawn_name]
		if (point.x < map_size.x / 2.0) != spawn_name.begins_with("SpawnA"):
			problems.append("%s is on the wrong side (team A left, team B right)." % spawn_name)
	return points


## Every straight line from an A spawn to a B spawn must cross a block, so nobody spawns
## in an enemy's sights. A line that only grazes a corner does not count as crossing.
func _check_sight(blocks: Array[ArenaBlock], spawns: Dictionary, problems: PackedStringArray) -> void:
	var outlines: Array[PackedVector2Array] = []
	for block: ArenaBlock in blocks:
		var rect: Rect2 = block_rect(block)
		outlines.append(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]))
	for a_name: String in spawns:
		if not a_name.begins_with("SpawnA"):
			continue
		for b_name: String in spawns:
			if b_name.begins_with("SpawnB") and not _line_blocked(spawns[a_name], spawns[b_name], outlines):
				problems.append("%s and %s can see each other. Move cover between them." % [a_name, b_name])


func _line_blocked(from: Vector2, to: Vector2, outlines: Array[PackedVector2Array]) -> bool:
	var line: PackedVector2Array = PackedVector2Array([from, to])
	for outline: PackedVector2Array in outlines:
		for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(line, outline):
			if piece[0].distance_to(piece[piece.size() - 1]) > 1.0:
				return true
	return false
