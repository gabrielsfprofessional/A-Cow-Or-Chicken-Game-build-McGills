class_name ArenaRules
extends MapRules
## The arena's rules (card T12). Server only. Owner: Adam (game/modes).
## A returning hero spawns on the allowed point farthest from the nearest living
## enemy (SpawnPicker), then gets spawn protection (data/arena_rules.tres).
## T15's mode extends this class with teams. Until then MatchRules' defaults hold:
## every point is allowed and every other hero is an enemy.

const DATA: ArenaRulesData = preload("res://game/modes/data/arena_rules.tres")

## Returns the living heroes as a Dictionary[int, Vector2], peer id -> global position
## (ArenaMap reads the world's Heroes node; tests pass a fake). Required.
var _living_heroes: Callable


func _init(points: Dictionary[String, Vector2], living_heroes: Callable) -> void:
	super(points)
	if not living_heroes.is_valid():
		push_error("ArenaRules: no way to read the living heroes, so spawns can't keep away from enemies. Pass a Callable that returns them.")
		living_heroes = func() -> Dictionary[int, Vector2]: return {}
	_living_heroes = living_heroes


## Overrides MapRules' pick, so respawn_point() and point_name() agree.
func pick(peer_id: int) -> int:
	var candidates := _candidates(peer_id)
	var points: Array[Vector2] = []
	for i: int in candidates:
		points.append(_points[i])
	var living: Dictionary[int, Vector2] = {}
	living.assign(_living_heroes.call())
	var enemies: Array[Vector2] = []
	var teammates: Array[Vector2] = []
	for other: int in living:
		if other == peer_id:
			continue
		if is_enemy(peer_id, other):
			enemies.append(living[other])
		else:
			teammates.append(living[other])
	var choice := SpawnPicker.pick(points, enemies, teammates, fposmod(float(peer_id) * RING_STEP, 1.0))
	return candidates[choice] if choice >= 0 else -1


func spawn_protection_sec() -> float:
	return DATA.spawn_protection_sec


## The points MapRules allows the peer's team, as in MapRules.pick() (it has no
## method of its own for this). test_arena_rules.gd checks the two agree.
func _candidates(peer_id: int) -> Array[int]:
	var team := team_of(peer_id)
	var candidates: Array[int] = []
	for i: int in _names.size():
		var point_team := MapList.team_of_spawn(_names[i])
		if team < 0 or point_team < 0 or point_team == team:
			candidates.append(i)
	if candidates.is_empty():
		for i: int in _names.size():
			candidates.append(i)
	return candidates
