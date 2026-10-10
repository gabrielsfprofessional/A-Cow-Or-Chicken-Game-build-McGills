class_name DelayQueue
extends RefCounted
## Holds (sequence, position) messages back to fake a slow network: --sim-lag and
## --sim-jitter (debug builds). Owner: Gabe (game/net). Card T07.
## Release time = max(previous release, now + lag + random 0..jitter), so messages
## never overtake each other, like unreliable_ordered. Pure: the clock is passed in.
## A preallocated ring buffer, so queueing allocates nothing.

const CAPACITY: int = 64

var lag_sec: float
var jitter_sec: float

var _release: PackedFloat64Array = PackedFloat64Array()
var _sequence: PackedInt64Array = PackedInt64Array()
var _position: PackedVector2Array = PackedVector2Array()
var _head: int = 0
var _count: int = 0
var _last_release_sec: float = -INF
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(lag_msec: int, jitter_msec: int, seed_value: int = 0) -> void:
	lag_sec = lag_msec / 1000.0
	jitter_sec = jitter_msec / 1000.0
	_release.resize(CAPACITY)
	_sequence.resize(CAPACITY)
	_position.resize(CAPACITY)
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func is_active() -> bool:
	return lag_sec > 0.0 or jitter_sec > 0.0


func size() -> int:
	return _count


func is_full() -> bool:
	return _count == CAPACITY


## Queues one message. The caller releases the oldest first when is_full();
## if it doesn't, the oldest is dropped.
func push(sequence: int, position: Vector2, now_sec: float) -> void:
	if _count == CAPACITY:
		pop()
	var release := maxf(_last_release_sec, now_sec + lag_sec + _rng.randf() * jitter_sec)
	_last_release_sec = release
	var slot := (_head + _count) % CAPACITY
	_release[slot] = release
	_sequence[slot] = sequence
	_position[slot] = position
	_count += 1


## True when the oldest queued message may go out.
func is_due(now_sec: float) -> bool:
	return _count > 0 and _release[_head] <= now_sec


func peek_sequence() -> int:
	return _sequence[_head]


func peek_position() -> Vector2:
	return _position[_head]


func peek_release() -> float:
	return _release[_head]


func pop() -> void:
	if _count == 0:
		return
	_head = (_head + 1) % CAPACITY
	_count -= 1


func clear() -> void:
	_head = 0
	_count = 0
