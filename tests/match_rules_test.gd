extends SceneTree
## Tests for the week-3 seams: MatchRules, SpawnProtection, shots passing
## through allies, Health.absorb and bots ignoring allies. Owner: Gabe.
## Run: godot --headless --path . --script res://tests/match_rules_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.
## A --script test compiles before the autoloads register, so this file can't
## name NetHero, Shots or the test world (they use Net and Events); the bot match
## covers them, and tests/respawn_test.gd loads heroes at run time. This file
## checks every rule they ask and the ShotSim they drive.

const MatchRulesScript: GDScript = preload("res://game/core/match_rules.gd")
const ShotSimScript: GDScript = preload("res://game/weapons/shot_sim.gd")
const HealthScene: PackedScene = preload("res://game/heroes/health.tscn")
const COMBAT: CombatData = preload("res://game/heroes/data/combat.tres")
const TICK: float = 1.0 / 60.0
const HERO_RADIUS: float = 20.0
const MAX_TICKS: int = 600
## Peers: 1 and 2 are Blue (team 0), 3 is Orange (team 1), 4 has no team.
const BLUE_A: int = 1
const BLUE_B: int = 2
const ORANGE: int = 3
const NO_TEAM: int = 4


## A 2-team mode, the way T15 would write one.
class TwoTeams:
	extends MatchRules
	var teams: Dictionary[int, int] = {1: 0, 2: 0, 3: 1}

	func team_of(peer_id: int) -> int:
		return teams.get(peer_id, -1)

	func is_enemy(a: int, b: int) -> bool:
		if a == b:
			return false
		var ta := team_of(a)
		var tb := team_of(b)
		return ta < 0 or tb < 0 or ta != tb

	func respawn_point(peer_id: int) -> Vector2:
		return Vector2(200.0, 540.0) if team_of(peer_id) == 0 else Vector2(1720.0, 540.0)

	func respawn_delay_sec(_peer_id: int) -> float:
		return 2.5

	func spawn_protection_sec() -> float:
		return 2.0


var _failed: int = 0
var _count: int = 0
var _world: Node2D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_defaults_match_today()
	_two_team_decisions()
	_respawn_uses_rules()
	_protection_until_its_end()
	_absorb_sends_zero()
	_bot_ignores_allies()
	_world = Node2D.new()
	root.add_child(_world)
	await _shots_pass_through_allies()
	print("MATCH RULES TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


## Before teams: no teams, everyone hits and heals everyone, the T06 ring,
## combat.tres respawn_sec, no protection.
func _defaults_match_today() -> void:
	var rules: MatchRules = MatchRulesScript.new()
	_expect_eq("default: no team", rules.team_of(BLUE_A), -1)
	_expect_true("default: others are enemies", rules.is_enemy(BLUE_A, BLUE_B) and rules.is_enemy(BLUE_A, ORANGE))
	_expect_true("default: never your own enemy", not rules.is_enemy(BLUE_A, BLUE_A))
	_expect_true("default: heals everyone", rules.can_heal(BLUE_A, BLUE_B) and rules.can_heal(BLUE_A, ORANGE) and rules.can_heal(BLUE_A, BLUE_A))
	_expect_eq("default: delay is combat.tres", rules.respawn_delay_sec(BLUE_A), COMBAT.respawn_sec)
	_expect_eq("default: no protection", rules.spawn_protection_sec(), 0.0)
	# The T06 ring, worked out here independently of match_rules.gd.
	for peer: int in [1, 2, 1055242639, 2147483647]:
		var angle := fposmod(float(peer) * 0.618034, 1.0) * TAU
		var ring := Vector2(960.0, 540.0) + Vector2(cos(angle), sin(angle)) * 260.0
		_expect_true("default: peer %d on the T06 ring" % peer, rules.respawn_point(peer).is_equal_approx(ring))


func _two_team_decisions() -> void:
	var rules := TwoTeams.new()
	_expect_true("teams: an ally is not an enemy", not rules.is_enemy(BLUE_A, BLUE_B))
	_expect_true("teams: the other team is", rules.is_enemy(BLUE_A, ORANGE) and rules.is_enemy(ORANGE, BLUE_B))
	# Shield Charge knocks back only is_enemy; the Heal Drone heals only can_heal.
	_expect_true("teams: heals an ally", rules.can_heal(BLUE_A, BLUE_B))
	_expect_true("teams: heals itself", rules.can_heal(ORANGE, ORANGE))
	_expect_true("teams: never heals an enemy", not rules.can_heal(BLUE_A, ORANGE) and not rules.can_heal(ORANGE, BLUE_A))
	_expect_true("teams: a healer with no team heals no one on a team", not rules.can_heal(NO_TEAM, ORANGE) and not rules.can_heal(NO_TEAM, BLUE_A))
	_expect_true("teams: it still heals itself", rules.can_heal(NO_TEAM, NO_TEAM))
	var peers: Array[int] = [BLUE_A, BLUE_B, ORANGE, NO_TEAM]
	_expect_eq("teams: allies_among is the teammates", rules.allies_among(BLUE_A, peers), [BLUE_B])
	_expect_eq("teams: no team, no allies", rules.allies_among(NO_TEAM, peers), [])
	var defaults: MatchRules = MatchRulesScript.new()
	_expect_eq("default: allies_among is empty", defaults.allies_among(BLUE_A, peers), [])


func _respawn_uses_rules() -> void:
	var rules := TwoTeams.new()
	_expect_true("respawn: Blue at its point", rules.respawn_point(BLUE_B).is_equal_approx(Vector2(200.0, 540.0)))
	_expect_true("respawn: Orange at its point", rules.respawn_point(ORANGE).is_equal_approx(Vector2(1720.0, 540.0)))
	_expect_eq("respawn: the rules' delay", rules.respawn_delay_sec(ORANGE), 2.5)


## Protected while now < start + duration, not from that moment on.
func _protection_until_its_end() -> void:
	var guard := SpawnProtection.new()
	_expect_true("protection: off before any respawn", not guard.is_protected(0.0))
	guard.start(10.0, 2.0)
	_expect_true("protection: on at the respawn", guard.is_protected(10.0))
	_expect_true("protection: on just before the end", guard.is_protected(11.999))
	_expect_true("protection: off exactly at the end", not guard.is_protected(12.0))
	_expect_true("protection: off after", not guard.is_protected(12.5))
	guard.start(20.0, 0.0)
	_expect_true("protection: 0 s means none", not guard.is_protected(20.0))
	guard.start(30.0, 2.0)
	guard.stop()
	_expect_true("protection: an elimination ends it", not guard.is_protected(30.5))


## A protected hit: damaged fires with 0 and health stays put, so the client
## still gets receive_damage and ends the shot there.
func _absorb_sends_zero() -> void:
	var health := HealthScene.instantiate() as Health
	root.add_child(health)
	var seen: Array[int] = []
	health.damaged.connect(func(amount: int, _a: int, _s: int, after: int, _at: Vector2) -> void:
		seen.append_array([amount, after]))
	health.absorb(ORANGE, 7, Vector2.ZERO)
	_expect_eq("absorb: one damaged signal, amount 0", seen, [0, 100])
	_expect_eq("absorb: health unchanged", health.health(), 100)
	health.take_damage(20, ORANGE, 8, Vector2.ZERO)
	_expect_eq("after protection: damage works", health.health(), 80)
	health.free()


func _bot_ignores_allies() -> void:
	var near_ally := BotRules.Seen.new(BLUE_B, Vector2(100.0, 0.0), true, true)
	var far_enemy := BotRules.Seen.new(ORANGE, Vector2(300.0, 0.0), true, true)
	var heroes: Array[BotRules.Seen] = [near_ally, far_enemy]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var bot := BotRules.new(rng, Rect2(0.0, 0.0, 1000.0, 1000.0))
	_expect_eq("bot, no teams: nearest hero", bot.pick_target(BLUE_A, Vector2.ZERO, heroes, 1000.0), BLUE_B)
	bot.set_team(BLUE_A, 0)
	bot.set_team(BLUE_B, 0)
	bot.set_team(ORANGE, 1)
	_expect_eq("bot, teams: skips the nearer ally", bot.pick_target(BLUE_A, Vector2.ZERO, heroes, 1000.0), ORANGE)
	var only_ally: Array[BotRules.Seen] = [near_ally]
	_expect_eq("bot, teams: no enemy, no target", bot.pick_target(BLUE_A, Vector2.ZERO, only_ally, 1000.0), 0)
	var untagged := BotRules.Seen.new(NO_TEAM, Vector2(50.0, 0.0), true, true)
	var with_untagged: Array[BotRules.Seen] = [near_ally, untagged]
	_expect_eq("bot, teams: a peer with no team is fair game", bot.pick_target(BLUE_A, Vector2.ZERO, with_untagged, 1000.0), NO_TEAM)


## Shooter (Blue), then an ally (Blue), then an enemy (Orange), in a line.
## With teams the shot passes the ally and hits the enemy; with the default
## rules (no teams) it hits the first hero, as before.
func _shots_pass_through_allies() -> void:
	var shooter := _make_hero(Vector2(200.0, 500.0))
	var ally := _make_hero(Vector2(320.0, 500.0))
	var enemy := _make_hero(Vector2(440.0, 500.0))
	var bodies: Dictionary[int, CharacterBody2D] = {BLUE_A: shooter, BLUE_B: ally, ORANGE: enemy}
	await physics_frame
	await physics_frame
	var teams := TwoTeams.new()
	var hit := await _fire(shooter, bodies, teams)
	_expect_true("teams: the shot passes the ally and hits the enemy", hit == enemy.get_node(^"Health"))
	_expect_eq("teams: the ally took no damage", (ally.get_node(^"Health") as Health).health(), 100)
	hit = await _fire(shooter, bodies, MatchRulesScript.new())
	_expect_true("default: the shot hits the first hero, as before", hit == ally.get_node(^"Health"))
	for body: CharacterBody2D in bodies.values():
		body.queue_free()


## One shot from the shooter along +x; the Health it hit, or null.
func _fire(shooter: CharacterBody2D, bodies: Dictionary[int, CharacterBody2D], rules: MatchRules) -> Health:
	var sim: ShotSim = ShotSimScript.new()
	var hits: Array[Health] = []
	sim.on_hit = func(_attacker: int, _shot: int, damage: int, health: Health, at: Vector2) -> void:
		health.take_damage(damage, _attacker, _shot, at)
		hits.append(health)
	# What Shots._allies_of does (MatchRules.allies_among), over this test's bodies.
	sim.allies_of = func(attacker: int) -> Array[RID]:
		var allies: Array[RID] = []
		var peers: Array[int] = []
		peers.assign(bodies.keys())
		for peer: int in rules.allies_among(attacker, peers):
			allies.append(bodies[peer].get_rid())
		return allies
	var data := WeaponData.new()
	data.damage = 20
	data.projectile_speed = 900.0
	data.projectile_radius = 6.0
	data.range_px = 1000.0
	var space := _world.get_world_2d().direct_space_state
	_expect_true("shot starts", sim.start(space, shooter.get_rid(), BLUE_A, 1, shooter.global_position, Vector2.RIGHT, data))
	var ticks := 0
	while sim.active_count() > 0 and ticks < MAX_TICKS:
		await physics_frame
		sim.step(space, TICK)
		ticks += 1
	return hits[0] if hits.size() == 1 else null


func _make_hero(at: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	var shape := CollisionShape2D.new()
	shape.name = "Collider"
	var circle := CircleShape2D.new()
	circle.radius = HERO_RADIUS
	shape.shape = circle
	body.add_child(shape)
	body.add_child(HealthScene.instantiate())
	body.position = at
	_world.add_child(body)
	return body


func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok   %s" % case_name)
	else:
		_failed += 1
		print("  FAIL %s" % case_name)


func _expect_eq(case_name: String, got: Variant, want: Variant) -> void:
	_count += 1
	if got == want:
		print("  ok   %s" % case_name)
	else:
		_failed += 1
		print("  FAIL %s: got %s, want %s" % [case_name, got, want])
