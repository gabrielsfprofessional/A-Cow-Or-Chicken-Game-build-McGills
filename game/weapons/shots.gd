class_name Shots
extends Node2D
## Every shot in the world: one node, child of the test world, drawn below the
## heroes. Owner: Gabe (game/weapons). Card T08.
##
## - On the server it runs a ShotSim every physics tick: those shots decide hits,
##   and a hit calls the hero's take_hit (spawn protection) or the Health's
##   take_damage. Shots pass through the shooter's teammates (the world's MatchRules).
## - On clients it draws shots: origin + direction x speed x age, ending at the
##   first wall (one cast_motion against layer 1 when the shot appears), at
##   range_px, or at the server's hit position (end_visual). Fixed arrays with
##   slot reuse; physics interpolation off, since positions come from the age.

const VISUAL_CAPACITY: int = 128
const WORLD_MASK: int = 1
const SHOT_COLOR: Color = Color(1.0, 0.86, 0.35)

var _sim: ShotSim = null

var _active: PackedByteArray = PackedByteArray()
var _attacker: PackedInt64Array = PackedInt64Array()
var _shot_id: PackedInt64Array = PackedInt64Array()
var _origin: PackedVector2Array = PackedVector2Array()
var _direction: PackedVector2Array = PackedVector2Array()
var _speed: PackedFloat32Array = PackedFloat32Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
## Distance along the direction where the shot stops being drawn.
var _end: PackedFloat32Array = PackedFloat32Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _visible_count: int = 0
var _wall_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
var _wall_shape: CircleShape2D = CircleShape2D.new()


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if Net.state == Net.State.SERVER:
		_sim = ShotSim.new()
		_sim.on_hit = _on_server_hit
		_sim.allies_of = _allies_of
		return
	set_physics_process(false)
	_active.resize(VISUAL_CAPACITY)
	_attacker.resize(VISUAL_CAPACITY)
	_shot_id.resize(VISUAL_CAPACITY)
	_origin.resize(VISUAL_CAPACITY)
	_direction.resize(VISUAL_CAPACITY)
	_speed.resize(VISUAL_CAPACITY)
	_radius.resize(VISUAL_CAPACITY)
	_end.resize(VISUAL_CAPACITY)
	_age.resize(VISUAL_CAPACITY)
	_wall_query.shape = _wall_shape
	_wall_query.collision_mask = WORLD_MASK
	_wall_query.collide_with_areas = false


func _physics_process(delta: float) -> void:
	if _sim != null:
		_sim.step(get_world_2d().direct_space_state, delta)


## Server: starts a shot from the shooter's center. False when it starts inside
## a wall (or the server is out of slots): then it must not be sent.
func start_server_shot(shooter: CollisionObject2D, attacker_id: int, shot_id: int,
		origin: Vector2, direction: Vector2, data: WeaponData) -> bool:
	if _sim == null:
		return false
	return _sim.start(get_world_2d().direct_space_state, shooter.get_rid(), attacker_id, shot_id,
		origin, direction, data)


## Server: drops every shot in flight without a hit (world.respawn_all(), a new
## match) and returns how many; 0 on clients. Clients keep drawing those shots
## until a wall or their range: only the server decides hits, so they hit nothing.
func clear_server_shots() -> int:
	return _sim.clear() if _sim != null else 0


## Client: draws a shot from now on. The shooter's own shot comes from its
## weapon at once; everyone else's from the server's message.
func add_visual(attacker_id: int, shot_id: int, origin: Vector2, direction: Vector2, data: WeaponData) -> void:
	if _sim != null or _active.is_empty():
		return
	var slot := _free_visual_slot()
	var dir := direction.normalized()
	_wall_shape.radius = data.projectile_radius
	_wall_query.transform = Transform2D(0.0, origin)
	_wall_query.motion = dir * data.range_px
	var fractions := get_world_2d().direct_space_state.cast_motion(_wall_query)
	var reach := data.range_px * (fractions[0] if fractions.size() == 2 else 1.0)
	if _active[slot] == 0:
		_visible_count += 1
	_active[slot] = 1
	_attacker[slot] = attacker_id
	_shot_id[slot] = shot_id
	_origin[slot] = origin
	_direction[slot] = dir
	_speed[slot] = data.projectile_speed
	_radius[slot] = data.projectile_radius
	_end[slot] = reach
	_age[slot] = 0.0


## Client: the server says this shot hit at `at`. It flies there and stops, or
## goes at once if it is already past.
func end_visual(attacker_id: int, shot_id: int, at: Vector2) -> void:
	for slot: int in range(_active.size()):
		if _active[slot] == 1 and _attacker[slot] == attacker_id and _shot_id[slot] == shot_id:
			_end[slot] = minf(_end[slot], maxf(0.0, (at - _origin[slot]).dot(_direction[slot])))
			if _speed[slot] * _age[slot] >= _end[slot]:
				_free_visual(slot)
			return


func _process(delta: float) -> void:
	if _visible_count == 0:
		return
	for slot: int in range(VISUAL_CAPACITY):
		if _active[slot] == 0:
			continue
		_age[slot] += delta
		if _speed[slot] * _age[slot] >= _end[slot]:
			_free_visual(slot)
	queue_redraw()


func _draw() -> void:
	for slot: int in range(_active.size()):
		if _active[slot] == 1:
			var travelled := minf(_speed[slot] * _age[slot], _end[slot])
			draw_circle(_origin[slot] + _direction[slot] * travelled, _radius[slot], SHOT_COLOR)


## A hero's own take_hit applies spawn protection; any other Health just takes it.
func _on_server_hit(attacker_id: int, shot_id: int, damage: int, health: Health, at: Vector2) -> void:
	var hero := health.get_parent() as NetHero
	if hero != null:
		hero.take_hit(attacker_id, shot_id, damage, at)
	else:
		health.take_damage(damage, attacker_id, shot_id, at)


## Server: the heroes this attacker's shots pass through (MatchRules.allies_among).
## Empty under the default rules, so only the shooter is skipped. Needs Shots
## to be a child of the world root and the heroes under its "Heroes" node.
func _allies_of(attacker_id: int) -> Array[RID]:
	var bodies: Array[RID] = []
	var world := get_parent()
	if world == null or not world.has_method(&"rules"):
		return bodies
	var rules := world.call(&"rules") as MatchRules
	var heroes := world.get_node_or_null(^"Heroes")
	if rules == null or heroes == null:
		return bodies
	var by_peer: Dictionary[int, RID] = {}
	var peers: Array[int] = []
	for child: Node in heroes.get_children():
		var hero := child as NetHero
		if hero != null:
			by_peer[hero.owner_peer] = hero.get_rid()
			peers.append(hero.owner_peer)
	for peer: int in rules.allies_among(attacker_id, peers):
		bodies.append(by_peer[peer])
	return bodies


## A free slot, or the oldest shot's when all are busy.
func _free_visual_slot() -> int:
	var oldest := 0
	for slot: int in range(VISUAL_CAPACITY):
		if _active[slot] == 0:
			return slot
		if _age[slot] > _age[oldest]:
			oldest = slot
	return oldest


func _free_visual(slot: int) -> void:
	_active[slot] = 0
	_visible_count -= 1
	if _visible_count == 0:
		queue_redraw()
