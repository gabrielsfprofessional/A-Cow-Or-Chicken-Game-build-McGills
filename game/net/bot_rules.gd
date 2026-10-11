class_name BotRules
extends RefCounted
## A test bot's decisions (card T09). Owner: Gabe (game/net). Pure: BotBrain
## passes in the clock, where things are and what it can see, and
## tests/bot_rules_test.gd drives it directly. Every random choice comes from the
## RandomNumberGenerator passed in, so the same seed and the same inputs make the
## same choices.
##
## - Walking: to a random point in the area. A new point on arrival, after
##   STUCK_SEC without getting PROGRESS_PX closer, or when the 4-8 s wander time
##   runs out.
## - Targeting, every LOOK_INTERVAL_SEC: the nearest live hero it can see within
##   range, never itself. Each look rolls a new aim error of up to AIM_ERROR_DEG.
## - Firing, only with a target: bursts of 0.5-1.5 s and pauses of 0.3-1 s,
##   starting with a burst.
## These are test-tool numbers, not gameplay, so they stay constants (no .tres).

const LOOK_INTERVAL_SEC: float = 0.25
## This close to the walk point counts as arrived.
const ARRIVE_PX: float = 24.0
## Getting this much closer than its best so far counts as progress.
const PROGRESS_PX: float = 8.0
## This long without progress counts as stuck.
const STUCK_SEC: float = 1.0
const WANDER_MIN_SEC: float = 4.0
const WANDER_MAX_SEC: float = 8.0
const AIM_ERROR_DEG: float = 6.0
const BURST_MIN_SEC: float = 0.5
const BURST_MAX_SEC: float = 1.5
const PAUSE_MIN_SEC: float = 0.3
const PAUSE_MAX_SEC: float = 1.0


## Another hero as the bot sees it, for pick_target().
class Seen:
	extends RefCounted
	var peer_id: int
	var position: Vector2
	var alive: bool
	## Nothing on the world layer between the bot and it.
	var visible: bool

	func _init(id: int, at: Vector2, is_alive: bool, in_sight: bool) -> void:
		peer_id = id
		position = at
		alive = is_alive
		visible = in_sight


## Where the bot is walking to.
var walk_point: Vector2 = Vector2.ZERO
## Peer id of the hero it shoots at; 0 when none.
var target: int = 0

var _rng: RandomNumberGenerator
var _area: Rect2
var _repick_at_sec: float = 0.0
var _closest_px: float = 0.0
var _progress_at_sec: float = 0.0
var _next_look_sec: float = 0.0
var _aim_error_rad: float = 0.0
var _firing: bool = false
## When the trigger next flips between burst and pause; -1 while not shooting.
var _switch_at_sec: float = -1.0


func _init(rng: RandomNumberGenerator, area: Rect2) -> void:
	_rng = rng
	_area = area


## Starts over from `from`: a new walk point, a look at once and no target.
## BotBrain calls it when the hero spawns and when it respawns.
func restart(now: float, from: Vector2) -> void:
	_pick_walk_point(now, from)
	_next_look_sec = now
	drop_target()


## The way to walk this tick: length 1, or 0 when exactly on the point.
func walk(now: float, from: Vector2) -> Vector2:
	var distance := from.distance_to(walk_point)
	if distance <= ARRIVE_PX or now >= _repick_at_sec or now - _progress_at_sec >= STUCK_SEC:
		_pick_walk_point(now, from)
	elif distance <= _closest_px - PROGRESS_PX:
		_closest_px = distance
		_progress_at_sec = now
	return from.direction_to(walk_point)


## True once every LOOK_INTERVAL_SEC: time to pick a target again.
func is_look_due(now: float) -> bool:
	if now < _next_look_sec:
		return false
	_next_look_sec = now + LOOK_INTERVAL_SEC
	return true


## Picks the nearest live, visible hero within range_px that isn't the bot
## itself, and rolls a new aim error. Returns its peer id (also in `target`),
## or 0 when there is none.
func pick_target(self_id: int, from: Vector2, heroes: Array[Seen], range_px: float) -> int:
	var best := 0
	var best_px := INF
	for seen: Seen in heroes:
		if seen.peer_id == self_id or not seen.alive or not seen.visible:
			continue
		var px := from.distance_to(seen.position)
		if px <= range_px and px < best_px:
			best = seen.peer_id
			best_px = px
	if best == 0:
		drop_target()
		return 0
	target = best
	_aim_error_rad = deg_to_rad(_rng.randf_range(-AIM_ERROR_DEG, AIM_ERROR_DEG))
	return target


## The aim offset toward target_position, turned by this look's aim error.
func aim_at(from: Vector2, target_position: Vector2) -> Vector2:
	return (target_position - from).rotated(_aim_error_rad)


## True while the trigger is held. Only with a target: a new one starts with a
## burst, then bursts and pauses take turns.
func trigger(now: float) -> bool:
	if target == 0:
		return false
	if _switch_at_sec < 0.0:
		_firing = true
		_switch_at_sec = now + _rng.randf_range(BURST_MIN_SEC, BURST_MAX_SEC)
	elif now >= _switch_at_sec:
		_firing = not _firing
		if _firing:
			_switch_at_sec = now + _rng.randf_range(BURST_MIN_SEC, BURST_MAX_SEC)
		else:
			_switch_at_sec = now + _rng.randf_range(PAUSE_MIN_SEC, PAUSE_MAX_SEC)
	return _firing


## No target: hold fire, and the next target starts with a fresh burst.
func drop_target() -> void:
	target = 0
	_firing = false
	_switch_at_sec = -1.0


func _pick_walk_point(now: float, from: Vector2) -> void:
	walk_point = Vector2(
		_rng.randf_range(_area.position.x, _area.end.x),
		_rng.randf_range(_area.position.y, _area.end.y))
	_repick_at_sec = now + _rng.randf_range(WANDER_MIN_SEC, WANDER_MAX_SEC)
	_closest_px = from.distance_to(walk_point)
	_progress_at_sec = now
