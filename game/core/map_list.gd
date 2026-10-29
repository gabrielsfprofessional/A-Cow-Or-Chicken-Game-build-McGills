class_name MapList
extends Resource
## The maps a server can run, by name (card T39). Owner: Gabe (game/core).
## The list itself, game/maps/data/maps.tres, is Adam's to edit: add a line per map.
## "test" is reserved: no map, just the test world.
## The map contract every listed scene keeps is in game/net/README.md, "Maps online".

const TEST: String = "test"
## Spawn points every map needs at least. The arena's own rule (8 team spawns) lives in
## game/maps/arena/arena_graybox.gd; the practice range has one.
const MIN_SPAWNS: int = 1
const SPAWNS_NODE: String = "Spawns"
## A spawn name may start with a team: SpawnA = team 0 (Blue), SpawnB = team 1 (Orange).
## Any other name (for example PlayerSpawn) is a spawn point for every team.
const TEAM_PREFIXES: PackedStringArray = ["SpawnA", "SpawnB"]

## Lowercase name -> scene path, for example "arena" -> "res://game/maps/arena/arena_graybox.tscn".
@export var maps: Dictionary[String, String] = {}


## The scene path for this map name, or "" for "test" and names not in the list.
func scene_path(map_name: String) -> String:
	return maps.get(map_name, "")


## One plain-words message per broken entry, naming it. Empty means the list passes.
## data_test runs this on maps.tres.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	if maps.is_empty():
		problems.append("the list has no maps")
	for map_name: String in maps:
		for problem: String in entry_problems(map_name, maps[map_name]):
			problems.append("%s: %s" % [map_name, problem])
	return problems


static func entry_problems(map_name: String, path: String) -> PackedStringArray:
	var problems: PackedStringArray = []
	if map_name == TEST:
		problems.append("\"test\" is reserved for the test world; pick another name")
	if map_name.is_empty() or map_name != map_name.to_lower() or map_name.contains(" "):
		problems.append("the name must be lowercase with no spaces")
	if not ResourceLoader.exists(path):
		problems.append("there is no scene at %s" % path)
		return problems
	var scene := ResourceLoader.load(path) as PackedScene
	if scene == null:
		problems.append("%s is not a scene" % path)
		return problems
	var root := scene.instantiate()
	problems.append_array(contract_problems(root))
	root.free()
	return problems


## What a map scene's root breaks of the map contract. The root need not be in the tree.
static func contract_problems(root: Node) -> PackedStringArray:
	var problems: PackedStringArray = []
	if not root is Node2D:
		problems.append("the scene's root must be a Node2D")
	var size: Variant = root.get(&"map_size")
	if not size is Vector2 or (size as Vector2).x <= 0.0 or (size as Vector2).y <= 0.0:
		problems.append("the root needs a map_size (Vector2, in px)")
	var spawns := root.get_node_or_null(SPAWNS_NODE)
	if spawns == null:
		problems.append("there is no %s node" % SPAWNS_NODE)
		return problems
	var count := 0
	for child: Node in spawns.get_children():
		if child is Marker2D:
			count += 1
		else:
			problems.append("%s/%s must be a Marker2D (a spawn point)" % [SPAWNS_NODE, child.name])
	if count < MIN_SPAWNS:
		problems.append("it has %d spawn points; it needs at least %d" % [count, MIN_SPAWNS])
	return problems


## 0 for SpawnA or SpawnA<number>, 1 for SpawnB or SpawnB<number>, -1 for anything
## else (so SpawnArea or SpawnBridge is a shared point, not a team one).
static func team_of_spawn(spawn_name: String) -> int:
	for team: int in TEAM_PREFIXES.size():
		var prefix: String = TEAM_PREFIXES[team]
		if spawn_name.begins_with(prefix):
			var rest := spawn_name.substr(prefix.length())
			if rest.is_empty() or rest.is_valid_int():
				return team
	return -1
