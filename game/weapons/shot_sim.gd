class_name ShotSim
extends RefCounted
## The server's shots in flight. Owner: Gabe (game/weapons). Card T08.
## No network code: Shots (shots.gd) drives it on the server, and
## tests/projectile_test.gd drives it directly.
##
## Each shot is a circle of the weapon's projectile_radius. It starts at the
## shooter's center and every physics tick:
## 1. intersect_shape at its position with zero motion. Godot's cast_motion
##    ignores anything the shape starts inside, so this catches a hero who
##    stepped onto the shot or overlaps the shooter.
## 2. cast_motion over the tick's motion, then get_rest_info at the unsafe
##    point for what it touched (intersect_shape there if that comes back empty).
## Layers 1 (world) and 2 (heroes); the shooter is always excluded, and so is
## every body allies_of returns for the attacker: shots pass through teammates
## (week-3 seams), since clients draw a shot until a wall or a hit. A body with a
## live Health child takes damage; anything else stops the shot like a wall.
## It expires after range_px. Fixed arrays with slot reuse and one reused query
## and shape: our code creates no nodes per tick; Godot's query calls still
## return small new values. allies_of is asked once per attacker per step
## (cached), so a busy fight costs one hero walk per shooter, not per shot.

const CAPACITY: int = 256
const WORLD_MASK: int = 1
const HIT_MASK: int = 1 | 2
## Most overlaps looked at when a shot starts a tick inside something.
const MAX_OVERLAPS: int = 8
const NO_ALLIES: Array[RID] = []

## Called once per hit: (attacker_id: int, shot_id: int, damage: int,
## health: Health, hit_position: Vector2). The shot is already gone.
var on_hit: Callable = Callable()
## Optional: (attacker_id: int) -> Array[RID], the bodies that attacker's shots
## pass through. Unset or empty: only the shooter (no teams).
var allies_of: Callable = Callable()
## allies_of answers for this step, by attacker id; cleared at each step's start.
var _allies_cache: Dictionary[int, Array] = {}
## Totals since this sim was made, for tests and logs.
var hits: int = 0
var stopped: int = 0
var expired: int = 0

var _active: PackedByteArray = PackedByteArray()
var _attacker: PackedInt64Array = PackedInt64Array()
var _shot_id: PackedInt64Array = PackedInt64Array()
var _damage: PackedInt64Array = PackedInt64Array()
var _shooter: Array[RID] = []
var _position: PackedVector2Array = PackedVector2Array()
var _direction: PackedVector2Array = PackedVector2Array()
var _speed: PackedFloat32Array = PackedFloat32Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
var _range_left: PackedFloat32Array = PackedFloat32Array()
var _free: PackedInt32Array = PackedInt32Array()
var _free_count: int = 0
var _query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
var _shape: CircleShape2D = CircleShape2D.new()
var _exclude: Array[RID] = [RID()]


func _init() -> void:
	_active.resize(CAPACITY)
	_attacker.resize(CAPACITY)
	_shot_id.resize(CAPACITY)
	_damage.resize(CAPACITY)
	_shooter.resize(CAPACITY)
	_position.resize(CAPACITY)
	_direction.resize(CAPACITY)
	_speed.resize(CAPACITY)
	_radius.resize(CAPACITY)
	_range_left.resize(CAPACITY)
	_free.resize(CAPACITY)
	for i: int in range(CAPACITY):
		_free[i] = CAPACITY - 1 - i
	_free_count = CAPACITY
	_query.shape = _shape
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_query.exclude = _exclude


## Starts a shot at origin (the shooter's center). False when it starts inside a
## wall or every slot is busy: then the shot never existed and is not sent.
func start(space: PhysicsDirectSpaceState2D, shooter: RID, attacker_id: int, shot_id: int,
		origin: Vector2, direction: Vector2, data: WeaponData) -> bool:
	if _free_count == 0:
		return false
	_prepare(shooter, data.projectile_radius, origin, WORLD_MASK)
	if not space.intersect_shape(_query, 1).is_empty():
		return false
	_free_count -= 1
	var slot := _free[_free_count]
	_active[slot] = 1
	_attacker[slot] = attacker_id
	_shot_id[slot] = shot_id
	_damage[slot] = data.damage
	_shooter[slot] = shooter
	_position[slot] = origin
	_direction[slot] = direction.normalized()
	_speed[slot] = data.projectile_speed
	_radius[slot] = data.projectile_radius
	_range_left[slot] = data.range_px
	return true


## Moves every shot one physics tick.
func step(space: PhysicsDirectSpaceState2D, delta: float) -> void:
	if _free_count == CAPACITY:
		return
	_allies_cache.clear()
	for slot: int in range(CAPACITY):
		if _active[slot] == 1:
			_step_one(space, slot, delta)


func active_count() -> int:
	return CAPACITY - _free_count


## The slot of a live shot, or -1.
func find(attacker_id: int, shot_id: int) -> int:
	for slot: int in range(CAPACITY):
		if _active[slot] == 1 and _attacker[slot] == attacker_id and _shot_id[slot] == shot_id:
			return slot
	return -1


func position_of(slot: int) -> Vector2:
	return _position[slot]


func _step_one(space: PhysicsDirectSpaceState2D, slot: int, delta: float) -> void:
	var from := _position[slot]
	var allies: Array[RID] = NO_ALLIES
	if allies_of.is_valid():
		var attacker := _attacker[slot]
		if not _allies_cache.has(attacker):
			var got: Array[RID] = []
			got.assign(allies_of.call(attacker))  # Also takes an untyped Array.
			_allies_cache[attacker] = got
		allies = _allies_cache[attacker]
	_prepare(_shooter[slot], _radius[slot], from, HIT_MASK, allies)
	var overlaps := space.intersect_shape(_query, MAX_OVERLAPS)
	if not overlaps.is_empty():
		_finish(slot, _first_live_health(overlaps), from)
		return
	var length := minf(_speed[slot] * delta, _range_left[slot])
	var motion := _direction[slot] * length
	_query.motion = motion
	var fractions := space.cast_motion(_query)
	if fractions.size() == 2 and fractions[1] < 1.0:
		_query.transform = Transform2D(0.0, from + motion * fractions[1])
		_query.motion = Vector2.ZERO
		var info := space.get_rest_info(_query)
		var target: Health = null
		if info.has("collider_id"):
			target = _live_health(instance_from_id(int(info["collider_id"])))
		else:
			# get_rest_info can miss a grazing touch; a hero there must not count as a wall.
			target = _first_live_health(space.intersect_shape(_query, MAX_OVERLAPS))
		_finish(slot, target, from + motion * fractions[0])
		return
	_position[slot] = from + motion
	_range_left[slot] -= length
	if _range_left[slot] <= 0.0:
		expired += 1
		_free_slot(slot)


## Ends a shot that touched something: damage when it is a live Health, else a wall.
func _finish(slot: int, target: Health, at: Vector2) -> void:
	var attacker_id := _attacker[slot]
	var shot_id := _shot_id[slot]
	var damage := _damage[slot]
	_free_slot(slot)
	if target == null:
		stopped += 1
		return
	hits += 1
	if on_hit.is_valid():
		on_hit.call(attacker_id, shot_id, damage, target, at)


## The first overlap with a live Health, or null (a wall, or nothing at all).
func _first_live_health(overlaps: Array[Dictionary]) -> Health:
	for overlap: Dictionary in overlaps:
		var target := _live_health(overlap.get("collider"))
		if target != null:
			return target
	return null


func _live_health(collider: Object) -> Health:
	var body := collider as Node
	if body == null:
		return null
	var health := body.get_node_or_null(^"Health") as Health
	return health if health != null and health.is_alive() else null


func _prepare(shooter: RID, radius: float, at: Vector2, mask: int, allies: Array[RID] = NO_ALLIES) -> void:
	if _shape.radius != radius:
		_shape.radius = radius
	_query.transform = Transform2D(0.0, at)
	_query.motion = Vector2.ZERO
	_query.collision_mask = mask
	if allies.is_empty():
		if _exclude.size() != 1 or _exclude[0] != shooter:
			_exclude.resize(1)
			_exclude[0] = shooter
			_query.exclude = _exclude
		return
	_exclude.resize(1)
	_exclude[0] = shooter
	_exclude.append_array(allies)
	_query.exclude = _exclude


func _free_slot(slot: int) -> void:
	_active[slot] = 0
	_shooter[slot] = RID()
	_free[_free_count] = slot
	_free_count += 1
