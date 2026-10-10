class_name RemoteTimeline
extends RefCounted
## Plays another player's hero back DELAY_SEC behind, smoothly. Owner: Gabe (game/net).
## Card T07. Pure logic: the clock is passed in, so tests/remote_timeline_test.gd can
## drive it. A preallocated ring buffer, so pushing and sampling allocate nothing.
##
## Each update's place on the sender's timeline is sequence x STEP_SEC. A slowly
## smoothed offset maps that onto the local clock. Playback chases
## (now - offset - DELAY_SEC) but never goes backward and never runs more than
## MAX_RATE_CHANGE fast or slow.

## One sequence step is one 20 Hz send.
const STEP_SEC: float = 0.05
const DELAY_SEC: float = 0.1
## Out of data: carry on along the last velocity this long, then hold.
const MAX_EXTRAPOLATE_SEC: float = 0.1
## Playback speed stays within 1 +/- this.
const MAX_RATE_CHANGE: float = 0.1
## How fast playback leans toward its target: 1 + error / CATCHUP_SEC, clamped.
const CATCHUP_SEC: float = 0.5
## Time constant of the clock offset smoothing.
const OFFSET_SMOOTH_SEC: float = 1.0
## Further behind than this (a long stall) jumps forward instead of catching up.
const RESYNC_SEC: float = 1.0
## A jump between updates longer than this clears the buffer and snaps.
const SNAP_DISTANCE: float = 200.0
const CAPACITY: int = 32

## Where to draw the hero, updated by sample().
var position: Vector2 = Vector2.ZERO
## Times the buffer ran dry (playback passed the newest update).
var underruns: int = 0
## The sender's time playback has reached, in seconds (sequence x STEP_SEC).
var playback_sec: float = 0.0
## The smoothed local-clock minus sender-time offset, in seconds.
var offset_sec: float = 0.0

var _time: PackedFloat64Array = PackedFloat64Array()
var _pos: PackedVector2Array = PackedVector2Array()
var _head: int = 0
var _count: int = 0
var _newest_sequence: int = -1
var _has_offset: bool = false
var _last_push_now: float = 0.0
var _started: bool = false
var _last_sample_now: float = 0.0
var _starved: bool = false
var _snapped: bool = false


func _init(start_position: Vector2 = Vector2.ZERO) -> void:
	position = start_position
	_time.resize(CAPACITY)
	_pos.resize(CAPACITY)


## Adds one update that arrived at local time now_sec. Old or repeated ones are ignored.
func push(sequence: int, new_position: Vector2, now_sec: float) -> void:
	if sequence <= _newest_sequence:
		return
	var sample_time := sequence * STEP_SEC
	if _count > 0 and _pos[_index(_count - 1)].distance_to(new_position) > SNAP_DISTANCE:
		_count = 0
		_head = 0
		position = new_position
		_snapped = true
	_newest_sequence = sequence
	_update_offset(now_sec - sample_time, now_sec)
	if _count == CAPACITY:
		_head = (_head + 1) % CAPACITY
		_count -= 1
	var slot := _index(_count)
	_time[slot] = sample_time
	_pos[slot] = new_position
	_count += 1


## Advances playback to local time now_sec and returns where to draw the hero.
func sample(now_sec: float) -> Vector2:
	if _count == 0:
		return position
	var target := now_sec - offset_sec - DELAY_SEC
	if not _started:
		_started = true
		playback_sec = target
	else:
		var dt := maxf(0.0, now_sec - _last_sample_now)
		var error := target - playback_sec
		if error > RESYNC_SEC:
			playback_sec = target
		else:
			var rate := clampf(1.0 + error / CATCHUP_SEC, 1.0 - MAX_RATE_CHANGE, 1.0 + MAX_RATE_CHANGE)
			playback_sec += dt * rate
	_last_sample_now = now_sec
	position = _position_at(playback_sec)
	return position


## True once after a snap, so the hero can reset physics interpolation.
func take_snap() -> bool:
	var snapped := _snapped
	_snapped = false
	return snapped


## How far the newest update is ahead of playback, in seconds. Negative when dry.
func buffer_depth_sec() -> float:
	if _count == 0:
		return 0.0
	return _time[_index(_count - 1)] - playback_sec


func _position_at(time_sec: float) -> Vector2:
	var newest := _index(_count - 1)
	if time_sec > _time[newest]:
		if not _starved:
			_starved = true
			underruns += 1
		if _count < 2:
			return _pos[newest]
		var previous := _index(_count - 2)
		var span := _time[newest] - _time[previous]
		var ahead := minf(time_sec - _time[newest], MAX_EXTRAPOLATE_SEC)
		return _pos[newest] + (_pos[newest] - _pos[previous]) * (ahead / span)
	_starved = false
	# Forget updates playback has left behind, keeping one at or before it.
	while _count >= 2 and _time[_index(1)] <= time_sec:
		_head = (_head + 1) % CAPACITY
		_count -= 1
	if time_sec <= _time[_head] or _count < 2:
		return _pos[_head]
	var next := _index(1)
	var weight := (time_sec - _time[_head]) / (_time[next] - _time[_head])
	return _pos[_head].lerp(_pos[next], weight)


func _update_offset(measured: float, now_sec: float) -> void:
	if not _has_offset:
		_has_offset = true
		offset_sec = measured
	else:
		var weight := clampf((now_sec - _last_push_now) / OFFSET_SMOOTH_SEC, 0.0, 1.0)
		offset_sec += (measured - offset_sec) * weight
	_last_push_now = now_sec


func _index(i: int) -> int:
	return (_head + i) % CAPACITY
