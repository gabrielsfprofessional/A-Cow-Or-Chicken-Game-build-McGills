@tool
class_name PracticeRange
extends GrayboxMap
## Graybox practice range: Floor, Walls, Cover, Spawns, Dummies, FlyCamera. Owner: Adam (game/maps).
## One room for one player. Dummies holds a Marker2D for each spot a target dummy will stand on;
## the dummies themselves come in the second half of T20, after T08.
## The shared map rules live in GrayboxMap; this adds the practice-only ones:
## exactly one PlayerSpawn, 1-8 dummy spots, and every spot with room around it.

const SPAWN_NAME: String = "PlayerSpawn"
const MIN_DUMMIES: int = 1
const MAX_DUMMIES: int = 8
const DUMMY_COLOR: Color = Color(0.85, 0.85, 0.85, 1)


func _check_layout(blocks: Array[ArenaBlock], _cover: Array[ArenaBlock], problems: PackedStringArray) -> Dictionary:
	var points: Dictionary = {}
	_check_spawn(blocks, points, problems)
	_check_dummies(blocks, points, problems)
	_check_spacing(points, problems)
	return points


func _walk_start() -> String:
	return SPAWN_NAME


func _marker_groups() -> Array[String]:
	return ["Spawns", "Dummies"]


func _marker_color(marker: Marker2D) -> Color:
	return ArenaMap.TEAM_A_COLOR if marker.name == SPAWN_NAME else DUMMY_COLOR


func _check_spawn(blocks: Array[ArenaBlock], points: Dictionary, problems: PackedStringArray) -> void:
	var group: Node = get_node_or_null(^"Spawns")
	if group == null:
		problems.append("There is no Spawns node.")
		return
	if group.get_child_count() != 1:
		problems.append("Spawns has %d children; the practice range needs exactly 1, named %s." % [group.get_child_count(), SPAWN_NAME])
	var marker: Marker2D = group.get_node_or_null(SPAWN_NAME) as Marker2D
	if marker == null:
		problems.append("Spawns/%s (a Marker2D) is missing." % SPAWN_NAME)
		return
	_check_marker(SPAWN_NAME, marker, blocks, points, problems)


func _check_dummies(blocks: Array[ArenaBlock], points: Dictionary, problems: PackedStringArray) -> void:
	var group: Node = get_node_or_null(^"Dummies")
	if group == null:
		problems.append("There is no Dummies node.")
		return
	var count: int = group.get_child_count()
	if count < MIN_DUMMIES or count > MAX_DUMMIES:
		problems.append("There are %d dummy spots; the practice range needs %d-%d." % [count, MIN_DUMMIES, MAX_DUMMIES])
	for child: Node in group.get_children():
		var spot: Marker2D = child as Marker2D
		if spot == null:
			problems.append("Dummies/%s is not a Marker2D. Only add Marker2D spots here." % child.name)
			continue
		_check_marker(_label(spot), spot, blocks, points, problems)


## The spawn and every dummy spot keep MIN_GAP apart, so two heroes fit between any two of them.
func _check_spacing(points: Dictionary, problems: PackedStringArray) -> void:
	var labels: Array = points.keys()
	for i: int in labels.size():
		for j: int in range(i + 1, labels.size()):
			var a: Vector2 = points[labels[i]]
			var b: Vector2 = points[labels[j]]
			if a.distance_to(b) < MIN_GAP:
				problems.append("%s and %s are %.0f px apart. Keep them at least %.0f px apart." % [labels[i], labels[j], a.distance_to(b), MIN_GAP])
