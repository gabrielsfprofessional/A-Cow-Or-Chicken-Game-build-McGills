class_name MapRules
extends MatchRules
## The default rules on one of Adam's maps (card T39): heroes spawn on the map's
## spawn points. Owner: Gabe (game/core).
##
## The world builds it from the map's Spawns markers and installs it with
## set_rules() before any hero spawns. A mode (T15) extends this class and
## installs its own the same way, so team_of() steers the pick:
## team 0 -> SpawnA points, team 1 -> SpawnB points, no team -> any point.
## The pick is stable per peer (the ring's golden-ratio step); T12 refines it.

var _names: Array[String] = []
var _points: Array[Vector2] = []


## Spawn points by name, in the world's coordinates. Sorted by name, so every
## run picks the same way.
func _init(points: Dictionary[String, Vector2] = {}) -> void:
	var names: Array[String] = []
	names.assign(points.keys())
	names.sort()
	for spawn_name: String in names:
		_names.append(spawn_name)
		_points.append(points[spawn_name])


## Rules from a map in the tree.
static func from_map(map: Node) -> MapRules:
	return MapRules.new(points_of(map))


## A map's spawn points by name, in the world's coordinates: every Marker2D under
## Spawns whose name gives a team. A mode builds its own subclass from these:
## MyRules.new(MapRules.points_of(map)).
static func points_of(map: Node) -> Dictionary[String, Vector2]:
	var points: Dictionary[String, Vector2] = {}
	var spawns := map.get_node_or_null(MapList.SPAWNS_NODE)
	if spawns != null:
		for child: Node in spawns.get_children():
			var marker := child as Marker2D
			if marker != null and MapList.team_of_spawn(marker.name) >= 0:
				points[String(marker.name)] = marker.global_position
	return points


func respawn_point(peer_id: int) -> Vector2:
	var index := pick(peer_id)
	return _points[index] if index >= 0 else super.respawn_point(peer_id)


## The spawn point's name, for the log. "" when the map has none.
func point_name(peer_id: int) -> String:
	var index := pick(peer_id)
	return _names[index] if index >= 0 else ""


## Index of the peer's spawn point, or -1 when there are none. A team with no
## points of its own uses all of them.
func pick(peer_id: int) -> int:
	var team := team_of(peer_id)
	var candidates: Array[int] = []
	for i: int in _names.size():
		if team < 0 or MapList.team_of_spawn(_names[i]) == team:
			candidates.append(i)
	if candidates.is_empty():
		for i: int in _names.size():
			candidates.append(i)
	if candidates.is_empty():
		return -1
	var slot := int(fposmod(float(peer_id) * RING_STEP, 1.0) * candidates.size())
	return candidates[mini(slot, candidates.size() - 1)]
