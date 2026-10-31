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
## The world's node that holds the heroes (game/net/README.md, "Match scene").
const HEROES_NODE: NodePath = ^"Heroes"


## Server: the arena's spawn rules (card T12). The world calls this when it builds the map
## (T39), so --map=arena uses them before any mode exists.
func make_rules() -> ArenaRules:
	var problem := heroes_problem(self)
	if problem != "":
		push_error(problem)
	var heroes: Node = get_parent().get_node_or_null(HEROES_NODE) if problem == "" else null
	return ArenaRules.new(MapRules.points_of(self), _living_heroes.bind(heroes))


## Why `map` can't see the world's heroes, in plain words; "" when it can. The world is
## the map's parent, and its heroes are the children of its Heroes node
## (game/net/README.md, "Match scene").
static func heroes_problem(map: Node) -> String:
	if map.get_parent() == null:
		return "ArenaMap: the map is not in a world, so spawns can't keep away from enemies."
	if map.get_parent().get_node_or_null(HEROES_NODE) == null:
		return "ArenaMap: the world has no Heroes node, so spawns can't keep away from enemies. The world must keep its heroes under Heroes."
	return ""


## Every living hero under `heroes` as peer id -> global position; none when `heroes` is null.
## Fails closed: a child that isn't a hero (no position, owner_peer or is_alive()) is named
## in an error and skipped. A dead hero is skipped quietly.
static func _living_heroes(heroes: Node) -> Dictionary[int, Vector2]:
	var living: Dictionary[int, Vector2] = {}
	if heroes == null:
		return living
	for hero: Node in heroes.get_children():
		if not (hero is Node2D and &"owner_peer" in hero and hero.has_method(&"is_alive")):
			push_error("ArenaMap: Heroes/%s is not a hero (it needs a 2D position, owner_peer and is_alive()), so spawns ignore it." % hero.name)
			continue
		if hero.call(&"is_alive"):
			living[int(hero.get(&"owner_peer"))] = (hero as Node2D).global_position
	return living


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
