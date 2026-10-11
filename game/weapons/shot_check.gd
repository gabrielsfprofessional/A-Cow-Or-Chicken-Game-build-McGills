class_name ShotCheck
extends RefCounted
## The server's check on one hero's fire messages. Owner: Gabe (game/weapons). Card T08.
## Pure logic: the clock is passed in, so tests/shot_check_test.gd can drive it.
##
## The rate rule is a schedule, not "time since the last accepted shot": each
## accepted shot books the next slot interval x RATE_SLACK later, and a shot may
## arrive up to JITTER_SEC before its slot. One late shot then never makes the
## next on-time one look early, the sustained rate stays within 1 / RATE_SLACK of
## the weapon's, and a pause buys at most JITTER_SEC of extra fire.

enum Result {
	ACCEPTED,
	WRONG_OWNER,   ## Sent by someone other than the hero's owner. Dropped.
	OLD_SHOT,      ## Shot id not newer than the last one. Dropped.
	OTHER_LIFE,    ## Fired in another life (before a death). Dropped.
	ELIMINATED,    ## The shooter is eliminated. Dropped.
	BAD_DIRECTION, ## NaN, INF or zero direction. Refused.
	TOO_SOON,      ## Faster than the weapon fires. Refused.
}

## Network jitter a shot may arrive early by, in seconds.
const JITTER_SEC: float = 0.25
## Shots are booked this fraction of the fire interval apart.
const RATE_SLACK: float = 0.9

var owner_id: int
var fire_interval_sec: float
var last_shot_id: int = 0
## The accepted shot's direction, normalized.
var direction: Vector2 = Vector2.RIGHT
## Refusals since the hero spawned (the dropped kinds not counted).
var refused: int = 0

var _next_sec: float = -INF


func _init(owner_peer: int, interval_sec: float) -> void:
	owner_id = owner_peer
	fire_interval_sec = interval_sec


## Checks one fire message. shot_life is the life it was fired in; current_life
## and alive are the shooter's now. On ACCEPTED, direction holds the normalized aim.
func check(sender_id: int, shot_id: int, shot_life: int, current_life: int, alive: bool,
		new_direction: Vector2, now_sec: float) -> Result:
	if sender_id != owner_id:
		return Result.WRONG_OWNER
	if shot_id <= last_shot_id:
		return Result.OLD_SHOT
	last_shot_id = shot_id
	if shot_life != current_life:
		return Result.OTHER_LIFE
	if not alive:
		return Result.ELIMINATED
	if not new_direction.is_finite() or new_direction.is_zero_approx():
		refused += 1
		return Result.BAD_DIRECTION
	if now_sec < _next_sec - JITTER_SEC:
		refused += 1
		return Result.TOO_SOON
	_next_sec = maxf(now_sec, _next_sec) + fire_interval_sec * RATE_SLACK
	direction = new_direction.normalized()
	return Result.ACCEPTED


static func result_name(result: Result) -> String:
	return Result.keys()[result].to_lower().replace("_", " ")
