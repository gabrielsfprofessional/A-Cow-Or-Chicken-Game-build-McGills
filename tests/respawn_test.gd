extends SceneTree
## Tests for a new match's respawn (the T15 seam): NetHero.respawn_now() and the
## ability effects a respawn ends. Owner: Gabe.
## Run: godot --headless --path . --script res://tests/respawn_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.
##
## NetHero and its abilities use the Net and Events autoloads. A --script test
## compiles before autoloads register, so a test that names those classes fails
## to compile. This one never names them: it loads net_hero.tscn at run time and
## drives the heroes through call() and get(). Offline, multiplayer.is_server()
## is true, so every hero runs its server side, and with no peers no RPC goes out.
## world.respawn_all() itself is covered by smoke's bot match.

const HERO_SCENE_PATH: String = "res://game/heroes/net_hero.tscn"
const ROSTER_PATH: String = "res://game/heroes/data/roster.tres"
## Roster slots.
const BRUISER: int = 0
const MAGE: int = 1
const MEDIC: int = 3
## This test waits on real time (the Heal Drone ticks every 0.5 s). An error
## after an await would hang it, so it fails itself after this long.
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


## A mode's rules: one respawn point, 2 s of spawn protection.
class PointRules:
	extends MatchRules
	const AT: Vector2 = Vector2(1500.0, 900.0)

	func respawn_point(_peer_id: int) -> Vector2:
		return AT

	func spawn_protection_sec() -> float:
		return 2.0


var _failed: int = 0
var _count: int = 0
var _hero_scene: PackedScene
var _roster: HeroRoster
var _world: FakeWorld
var _heroes: Node2D
var _respawned: Array = []
var _knocked: Array = []


func _initialize() -> void:
	create_timer(DEADLINE_SEC).timeout.connect(_on_deadline)
	_run()


func _on_deadline() -> void:
	printerr("  FAIL  the test did not finish within %d s (a script error after an await?)" % roundi(DEADLINE_SEC))
	quit(1)


func _run() -> void:
	_hero_scene = load(HERO_SCENE_PATH) as PackedScene
	_roster = load(ROSTER_PATH) as HeroRoster
	_world = FakeWorld.new()
	_world.name = "World"
	root.add_child(_world)
	_heroes = Node2D.new()
	_heroes.name = "Heroes"
	_world.add_child(_heroes)
	var events := root.get_node(^"Events")
	events.connect(&"hero_respawned", func(peer_id: int, at: Vector2) -> void: _respawned.append([peer_id, at]))
	events.connect(&"hero_knocked_back", func(victim: int, attacker: int) -> void: _knocked.append([victim, attacker]))
	_not_in_tree()
	await _live_hero_comes_back()
	await _eliminated_hero_comes_back()
	await _heal_drone_stops()
	await _dash_sweep_ends()
	print("RESPAWN TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


## A hero that never entered the tree has no server side yet.
func _not_in_tree() -> void:
	var loose := _hero_scene.instantiate()
	loose.call(&"setup", 51, Vector2(10.0, 10.0), Color.WHITE, _roster.at(BRUISER))
	var ok: bool = loose.call(&"respawn_now")
	_expect(not ok and loose.get(&"life") == 0, "a hero not in the tree: respawn_now() is false and changes nothing")
	loose.free()


## A live, hurt hero with a motion grant comes back like after a death.
func _live_hero_comes_back() -> void:
	_world.rules_now = PointRules.new()
	var hero := await _add_hero(11, BRUISER, Vector2(400.0, 300.0))
	hero.call(&"take_hit", 99, 1, 30, Vector2.ZERO)
	hero.call(&"grant_motion", 200.0, 1.0)
	var check: Object = hero.get(&"_check")
	_expect(hero.call(&"is_alive") and _health(hero) == 70 and is_equal_approx(check.get(&"grant_px"), 200.0),
		"before: alive, 70 HP, a 200 px motion grant")
	_respawned.clear()
	var ok: bool = hero.call(&"respawn_now")
	_expect(ok, "respawn_now() works on the server")
	_expect(hero.get(&"life") == 1, "a new life (life %d)" % hero.get(&"life"))
	_expect(_health(hero) == 100, "full health (%d HP)" % _health(hero))
	_expect(hero.get(&"global_position") == PointRules.AT, "at the rules' respawn point")
	_expect(check.get(&"position") == PointRules.AT and is_zero_approx(check.get(&"grant_px")),
		"MoveCheck starts there with no grant")
	_expect(hero.call(&"is_protected"), "the rules' spawn protection")
	_expect(_respawned == [[11, PointRules.AT]], "hero_respawned once, with the point (%s)" % str(_respawned))
	await _clear_heroes()


## An eliminated hero comes back at once, shown and hittable again.
func _eliminated_hero_comes_back() -> void:
	_world.rules_now = MatchRules.new()
	var hero := await _add_hero(21, MAGE, Vector2(400.0, 300.0))
	var collider := hero.get_node(^"Collider") as CollisionShape2D
	hero.call(&"take_hit", 99, 2, 999, Vector2.ZERO)
	_expect(not hero.call(&"is_alive") and not hero.get(&"visible") and collider.disabled,
		"before: eliminated, hidden, collider off")
	var ok: bool = hero.call(&"respawn_now")
	_expect(ok and hero.call(&"is_alive") and hero.get(&"visible") and not collider.disabled,
		"respawn_now() brings an eliminated hero back: alive, shown, collider on")
	_expect(hero.get(&"life") == 1 and _health(hero) == 100, "with a new life and full health")
	await _clear_heroes()


## The Heal Drone heals until its healer respawns, then stops (no protection here,
## so the hits land).
func _heal_drone_stops() -> void:
	_world.rules_now = MatchRules.new()
	var medic := await _add_hero(31, MEDIC, Vector2(800.0, 300.0))
	var drone := medic.get_node(^"Ability")
	medic.call(&"take_hit", 99, 3, 40, Vector2.ZERO)
	drone.call(&"_use_on_server", _now_sec())
	await create_timer(0.75).timeout
	_expect(_health(medic) > 60, "the drone heals before the respawn (%d HP from 60)" % _health(medic))
	medic.call(&"respawn_now")
	medic.call(&"take_hit", 99, 4, 40, Vector2.ZERO)
	await create_timer(1.25).timeout
	_expect(_health(medic) == 60, "after the respawn it heals no more (%d HP, want 60)" % _health(medic))
	_expect(drone.get(&"_ticks_left") == 0, "and its ticks are gone")
	await _clear_heroes()


## A dash's knockback sweep works in the dasher's life and ends at its respawn.
func _dash_sweep_ends() -> void:
	_world.rules_now = MatchRules.new()
	var dasher := await _add_hero(41, BRUISER, Vector2(200.0, 700.0))
	var victim := await _add_hero(42, MAGE, Vector2(360.0, 700.0))
	await physics_frame
	var charge := dasher.get_node(^"Ability")
	var from := Vector2(200.0, 700.0)
	var to := Vector2(440.0, 700.0)
	_knocked.clear()
	charge.call(&"_use_on_server", _now_sec())
	charge.call(&"on_server_moved", from, to)
	_expect(_knocked == [[42, 41]], "a dash knocks back an enemy in its path (%s)" % str(_knocked))
	charge.call(&"_use_on_server", _now_sec())
	charge.call(&"on_server_moved", from, to)
	_expect(_knocked.size() == 2, "a second dash in the same life knocks it back again")
	charge.call(&"_use_on_server", _now_sec())
	dasher.call(&"respawn_now")
	charge.call(&"on_server_moved", from, to)
	_expect(_knocked.size() == 2, "a dash from before the dasher's respawn knocks back no one (%d knockbacks)" % _knocked.size())
	_expect(victim.call(&"is_alive"), "the victim is untouched otherwise")
	await _clear_heroes()


## A hero in the world, past its _ready() and in the physics space.
func _add_hero(peer_id: int, slot: int, at: Vector2) -> Node:
	var hero := _hero_scene.instantiate()
	hero.call(&"setup", peer_id, at, Color.WHITE, _roster.at(slot))
	_heroes.add_child(hero)
	await physics_frame
	await physics_frame
	return hero


func _clear_heroes() -> void:
	for hero: Node in _heroes.get_children():
		hero.queue_free()
	await process_frame


func _health(hero: Node) -> int:
	return (hero.get_node(^"Health") as Health).health()


## The heroes' clock (NetHero._now_sec()).
func _now_sec() -> float:
	return Time.get_ticks_usec() / 1000000.0


func _expect(ok: bool, case_name: String) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)
