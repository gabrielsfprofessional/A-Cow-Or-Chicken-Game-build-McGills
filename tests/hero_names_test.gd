extends SceneTree
## Tests for the names seam (for T17): a hero's spawn data carries its player's name, and
## the hero shows it above itself. Owner: Gabe.
## Run: godot --headless --path . --script res://tests/hero_names_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.
##
## The test world and NetHero use the Net and Events autoloads. A --script test compiles
## before autoloads register, so a test that names those classes fails to compile. This
## one loads them at run time and drives them through call() and get(): the test world's
## spawn function (_make_hero(), the code every peer runs on spawn data) builds the heroes,
## and a stand-in world holds them for their labels. That the server puts each player's
## name in the spawn data, and every window gets it, is smoke's "player saves" stage.

const WORLD_SCENE_PATH: String = "res://game/net/test_world.tscn"
const ROSTER_PATH: String = "res://game/heroes/data/roster.tres"
## Roster slots.
const BRUISER: int = 0
const MAGE: int = 1
const SPOT: Vector2 = Vector2(400.0, 300.0)
## An error after an await would hang the test, so it fails itself after this long.
const DEADLINE_SEC: float = 20.0


## Stands in for the test world: the parent of "Heroes", answering what a hero asks.
class FakeWorld:
	extends Node2D
	var rules_now: MatchRules = MatchRules.new()

	func rules() -> MatchRules:
		return rules_now

	func respawn_point(peer_id: int) -> Vector2:
		return rules_now.respawn_point(peer_id)

	func is_peer_ready(_peer_id: int) -> bool:
		return false


var _failed: int = 0
var _count: int = 0
var _roster: HeroRoster
## test_world.tscn, never in the tree: only its spawn function runs.
var _spawn_world: Node
var _world: FakeWorld
var _heroes: Node2D


func _initialize() -> void:
	create_timer(DEADLINE_SEC).timeout.connect(_on_deadline)
	_run()


func _on_deadline() -> void:
	printerr("  FAIL  the test did not finish within %d s (a script error after an await?)" % roundi(DEADLINE_SEC))
	quit(1)


func _run() -> void:
	_roster = load(ROSTER_PATH) as HeroRoster
	_spawn_world = (load(WORLD_SCENE_PATH) as PackedScene).instantiate()
	_world = FakeWorld.new()
	_world.name = "World"
	root.add_child(_world)
	_heroes = Node2D.new()
	_heroes.name = "Heroes"
	_world.add_child(_heroes)
	_names_from_spawn_data()
	await _a_player_shows_their_name()
	await _a_guest_shows_their_peer()
	_spawn_world.free()
	print("HERO NAMES TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


## What each kind of spawn data makes: a name, or "" for a guest.
func _names_from_spawn_data() -> void:
	var cases: Array = [
		["a player's name", [21, BRUISER, SPOT, "Gabe"], "Gabe"],
		["a guest's \"\"", [22, BRUISER, SPOT, ""], ""],
		["no name (a net8 server's)", [23, BRUISER, SPOT], ""],
		["a name that isn't text", [24, BRUISER, SPOT, 42], ""],
		["a name that breaks the profile rules", [25, BRUISER, SPOT, "Ga\nbe"], ""],
		["spaces around the name (trimmed)", [26, BRUISER, SPOT, "  Zoë "], "Zoë"],
	]
	for entry: Array in cases:
		var hero: Node = _spawn_world.call(&"_make_hero", entry[1])
		var got: String = hero.get(&"player_name")
		_expect(got == entry[2], "spawn data with %s: player_name %s" % [entry[0], JSON.stringify(got)])
		hero.free()
	var mage: Node = _spawn_world.call(&"_make_hero", [27, MAGE, SPOT, "Ann"])
	_expect(mage.get(&"owner_peer") == 27 and mage.get(&"hero_data") == _roster.at(MAGE) and mage.get(&"position") == SPOT,
		"the name changes nothing else: peer 27, the mage, at the spot")
	mage.free()


func _a_player_shows_their_name() -> void:
	var hero := await _add_hero([31, BRUISER, SPOT, "Gabe"])
	var bruiser := _roster.at(BRUISER)
	_expect(hero.call(&"shown_name") == "Gabe", "shown_name() is the player's name")
	_expect(_label(hero) == "Gabe  %s  %d" % [bruiser.display_name, bruiser.max_health],
		"the label above the hero shows it (%s)" % JSON.stringify(_label(hero)))
	hero.call(&"take_hit", 99, 1, 30, Vector2.ZERO)
	_expect(_label(hero) == "Gabe  %s  %d" % [bruiser.display_name, bruiser.max_health - 30],
		"a hit changes the health and keeps the name (%s)" % JSON.stringify(_label(hero)))
	await _clear_heroes()


func _a_guest_shows_their_peer() -> void:
	var hero := await _add_hero([32, MAGE, SPOT, ""])
	var mage := _roster.at(MAGE)
	_expect(hero.call(&"shown_name") == "Player 32", "a guest's shown_name() is \"Player <peer id>\", as the [Combat] lines say")
	_expect(_label(hero) == "Player 32  %s  %d" % [mage.display_name, mage.max_health],
		"a guest's label is the one every hero had before (%s)" % JSON.stringify(_label(hero)))
	await _clear_heroes()


## A hero built from spawn data, in the world, past its _ready().
func _add_hero(spawn: Array) -> Node:
	var hero: Node = _spawn_world.call(&"_make_hero", spawn)
	_heroes.add_child(hero)
	await physics_frame
	await physics_frame
	return hero


func _clear_heroes() -> void:
	for hero: Node in _heroes.get_children():
		hero.queue_free()
	await process_frame


func _label(hero: Node) -> String:
	return (hero.get_node(^"PlayerName") as Label).text


func _expect(ok: bool, case_name: String) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)
