extends SceneTree
## Tests for ShotSim, the server's shots in flight (card T08). Owner: Gabe.
## Run: godot --headless --path . --script res://tests/projectile_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.
##
## A real physics world: a wall on layer 1, a shooter and a target on layer 2
## (the target has a Health child). Bodies that were added or moved reach
## queries only after the next physics step, so every case awaits one.

const ShotSimScript: GDScript = preload("res://game/weapons/shot_sim.gd")
const HealthScene: PackedScene = preload("res://game/heroes/health.tscn")
const TICK: float = 1.0 / 60.0
const SHOOTER_AT: Vector2 = Vector2(200.0, 500.0)
## Somewhere no shot in these cases goes near.
const PARKED: Vector2 = Vector2(5000.0, 5000.0)
const HERO_RADIUS: float = 20.0
const MAX_TICKS: int = 600

var _failed: int = 0
var _count: int = 0
var _world: Node2D
var _shooter: CharacterBody2D
var _target: CharacterBody2D
var _wall: StaticBody2D
var _hits: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_world()
	await physics_frame
	await physics_frame
	await _fast_shot_never_tunnels()
	await _wall_blocks()
	await _expires_at_range()
	await _target_steps_onto_shot()
	await _target_overlaps_shooter()
	await _starts_inside_wall()
	await _shooter_never_hit()
	await _disabled_collider_passes()
	await _clear_drops_every_shot()
	await _clear_inside_a_hit()
	print("PROJECTILE TEST: %s (%d checks)" % ["PASS" if _failed == 0 else "FAIL, %d wrong" % _failed, _count])
	quit(0 if _failed == 0 else 1)


func _build_world() -> void:
	_world = Node2D.new()
	root.add_child(_world)
	_wall = StaticBody2D.new()
	_wall.collision_layer = 1
	_wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20.0, 400.0)
	wall_shape.shape = rect
	_wall.add_child(wall_shape)
	_wall.position = PARKED
	_world.add_child(_wall)
	_shooter = _make_hero(SHOOTER_AT, false)
	_target = _make_hero(PARKED + Vector2(500, 0), true)


func _make_hero(at: Vector2, with_health: bool) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	var shape := CollisionShape2D.new()
	shape.name = "Collider"
	var circle := CircleShape2D.new()
	circle.radius = HERO_RADIUS
	shape.shape = circle
	body.add_child(shape)
	if with_health:
		body.add_child(HealthScene.instantiate())
	body.position = at
	_world.add_child(body)
	return body


func _weapon(speed: float, range_px: float) -> WeaponData:
	var data := WeaponData.new()
	data.damage = 20
	data.projectile_speed = speed
	data.projectile_radius = 6.0
	data.range_px = range_px
	return data


func _new_sim() -> ShotSim:
	var sim: ShotSim = ShotSimScript.new()
	_hits.clear()
	sim.on_hit = func(attacker: int, shot_id: int, damage: int, health: Health, at: Vector2) -> void:
		_hits.append({"attacker": attacker, "shot": shot_id, "damage": damage, "health": health, "at": at})
	return sim


## Puts the wall and target where a case wants them and lets physics catch up.
func _place(wall_at: Vector2, target_at: Vector2) -> void:
	_wall.position = wall_at
	_target.global_position = target_at
	(_target.get_node(^"Collider") as CollisionShape2D).disabled = false
	_shooter.global_position = SHOOTER_AT
	await physics_frame
	await physics_frame


func _space() -> PhysicsDirectSpaceState2D:
	return _world.get_world_2d().direct_space_state


func _start(sim: ShotSim, shot_id: int, direction: Vector2, data: WeaponData, origin: Vector2 = SHOOTER_AT) -> bool:
	return sim.start(_space(), _shooter.get_rid(), 7, shot_id, origin, direction, data)


## Steps the sim once per physics frame until no shot is left. Returns the ticks used.
func _run_out(sim: ShotSim) -> int:
	var ticks := 0
	while sim.active_count() > 0 and ticks < MAX_TICKS:
		await physics_frame
		sim.step(_space(), TICK)
		ticks += 1
	return ticks


func _fast_shot_never_tunnels() -> void:
	# 100 px a tick against a 40 px hero. Ticks land at x = 300 and 400, either
	# side of the hero at 350, so a shot that only checked where it lands would miss.
	await _place(PARKED, Vector2(350.0, 500.0))
	var sim := _new_sim()
	_start(sim, 1, Vector2.RIGHT, _weapon(6000.0, 900.0))
	await _run_out(sim)
	_expect_true("a 100 px/tick shot hits a 40 px hero between ticks (hits %d)" % _hits.size(), _hits.size() == 1)
	if _hits.size() == 1:
		var at: Vector2 = _hits[0].at
		_expect_true("the hit is reported where the shot touched (x %.1f)" % at.x, absf(at.x - (350.0 - HERO_RADIUS - 6.0)) < 2.0)
		_expect_true("with the attacker, shot id and damage", _hits[0].attacker == 7 and _hits[0].shot == 1 and _hits[0].damage == 20)
		_expect_true("on the target's Health", _hits[0].health == _target.get_node(^"Health"))


func _wall_blocks() -> void:
	await _place(Vector2(400.0, 500.0), Vector2(600.0, 500.0))
	var sim := _new_sim()
	_start(sim, 1, Vector2.RIGHT, _weapon(900.0, 900.0))
	await _run_out(sim)
	_expect_true("a wall in front blocks the shot", _hits.is_empty() and sim.stopped == 1)


func _expires_at_range() -> void:
	await _place(PARKED, PARKED + Vector2(500, 0))
	var sim := _new_sim()
	_start(sim, 1, Vector2.RIGHT, _weapon(900.0, 300.0))
	var furthest := 0.0
	var ticks := 0
	while sim.active_count() > 0 and ticks < MAX_TICKS:
		await physics_frame
		sim.step(_space(), TICK)
		var slot := sim.find(7, 1)
		if slot >= 0:
			furthest = maxf(furthest, sim.position_of(slot).x - SHOOTER_AT.x)
		ticks += 1
	_expect_true("the shot expires at its range (%d ticks, %.1f px)" % [ticks, furthest],
		sim.expired == 1 and furthest <= 300.0 + 0.01 and ticks == 20)


func _target_steps_onto_shot() -> void:
	await _place(PARKED, PARKED + Vector2(500, 0))
	var sim := _new_sim()
	_start(sim, 1, Vector2.RIGHT, _weapon(60.0, 900.0))
	await physics_frame
	sim.step(_space(), TICK)
	# The hero steps right on top of the slow shot between two ticks.
	_target.global_position = sim.position_of(sim.find(7, 1))
	await physics_frame
	sim.step(_space(), TICK)
	_expect_true("a hero who steps onto a shot is hit", _hits.size() == 1)
	await _run_out(sim)


func _target_overlaps_shooter() -> void:
	await _place(PARKED, SHOOTER_AT + Vector2(5.0, 0.0))
	var sim := _new_sim()
	_start(sim, 1, Vector2.LEFT, _weapon(900.0, 900.0))
	await _run_out(sim)
	_expect_true("a hero overlapping the shooter is hit", _hits.size() == 1)


func _starts_inside_wall() -> void:
	await _place(Vector2(400.0, 500.0), PARKED + Vector2(500, 0))
	var sim := _new_sim()
	var started := _start(sim, 1, Vector2.RIGHT, _weapon(900.0, 900.0), Vector2(400.0, 500.0))
	_expect_true("a shot that starts inside a wall never starts", not started and sim.active_count() == 0)


func _shooter_never_hit() -> void:
	await _place(PARKED, PARKED + Vector2(500, 0))
	var sim := _new_sim()
	_start(sim, 1, Vector2.RIGHT, _weapon(300.0, 900.0))
	for i: int in range(5):
		await physics_frame
		sim.step(_space(), TICK)
	# The shooter runs onto its own shot (and ahead of it).
	_shooter.global_position = sim.position_of(sim.find(7, 1))
	await physics_frame
	sim.step(_space(), TICK)
	_shooter.global_position = sim.position_of(sim.find(7, 1)) + Vector2(15.0, 0.0)
	await _run_out(sim)
	_expect_true("the shooter is never hit, even on top of its own shot", _hits.is_empty() and sim.expired == 1)


func _disabled_collider_passes() -> void:
	await _place(PARKED, Vector2(500.0, 500.0))
	var sim := _new_sim()
	# Disabling takes effect at once: no physics frame in between.
	(_target.get_node(^"Collider") as CollisionShape2D).disabled = true
	_start(sim, 1, Vector2.RIGHT, _weapon(900.0, 600.0))
	await _run_out(sim)
	_expect_true("a disabled collider lets the shot pass", _hits.is_empty() and sim.expired == 1)


## A new match (world.respawn_all()): clear() drops every shot, counts them, and
## leaves every slot free for the next ones.
func _clear_drops_every_shot() -> void:
	await _place(PARKED, PARKED + Vector2(500, 0))
	var sim := _new_sim()
	for shot_id: int in range(1, 4):
		_start(sim, shot_id, Vector2.RIGHT, _weapon(300.0, 900.0))
	await physics_frame
	sim.step(_space(), TICK)
	var dropped := sim.clear()
	_expect_true("clear() drops every shot in flight (dropped %d, %d left)" % [dropped, sim.active_count()],
		dropped == 3 and sim.active_count() == 0 and sim.cleared == 3 and sim.find(7, 1) == -1)
	_expect_true("a cleared shot is not a hit, a stop or an expiry",
		_hits.is_empty() and sim.hits == 0 and sim.stopped == 0 and sim.expired == 0)
	_expect_true("clear() with nothing in flight drops nothing", sim.clear() == 0 and sim.cleared == 3)
	var started := 0
	for shot_id: int in range(10, 11 + ShotSim.CAPACITY):
		if _start(sim, shot_id, Vector2.RIGHT, _weapon(300.0, 900.0)):
			started += 1
	_expect_true("every slot is free again after clear() (%d of %d started)" % [started, ShotSim.CAPACITY + 1],
		started == ShotSim.CAPACITY and sim.active_count() == ShotSim.CAPACITY)
	_expect_true("clear() empties a full sim", sim.clear() == ShotSim.CAPACITY and sim.active_count() == 0)


## clear() from on_hit, inside step(): the shot right behind the one that hit,
## due later in the same tick, never lands.
func _clear_inside_a_hit() -> void:
	await _place(PARKED, Vector2(350.0, 500.0))
	var sim := _new_sim()
	sim.on_hit = func(attacker: int, shot_id: int, damage: int, health: Health, at: Vector2) -> void:
		_hits.append({"attacker": attacker, "shot": shot_id, "damage": damage, "health": health, "at": at})
		sim.clear()
	# Two shots on one path, 100 px a tick: both reach the hero in the same tick.
	_start(sim, 1, Vector2.RIGHT, _weapon(6000.0, 900.0))
	_start(sim, 2, Vector2.RIGHT, _weapon(6000.0, 900.0))
	await _run_out(sim)
	_expect_true("clear() inside a hit stops the shot behind it (hits %d, cleared %d)" % [_hits.size(), sim.cleared],
		_hits.size() == 1 and _hits[0].shot == 1 and sim.cleared == 1 and sim.active_count() == 0)
	var started := 0
	for shot_id: int in range(10, 10 + ShotSim.CAPACITY):
		if _start(sim, shot_id, Vector2.LEFT, _weapon(300.0, 900.0)):
			started += 1
	_expect_true("every slot is free after clear() inside step() (%d started)" % started, started == ShotSim.CAPACITY)
	sim.on_hit = Callable()  # The callback holds sim: break the cycle so nothing leaks.
	sim.clear()


func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)
