class_name MoveCheck
extends RefCounted
## The server's check on one hero's movement updates. Owner: Gabe (game/net). Card T07.
## Pure logic: the clock is passed in, so tests/move_check_test.gd can drive it.
## The position it keeps is the server's copy of the hero, which T08 hit-tests.

enum Result {
	ACCEPTED,
	WRONG_OWNER,   ## Sent by someone other than the hero's owner. Dropped.
	OLD_SEQUENCE,  ## Not newer than the last one. Dropped.
	NOT_FINITE,    ## NaN or INF in the position.
	OUT_OF_BOUNDS, ## A coordinate beyond +/-MAX_COORD.
	OVER_BUDGET,   ## Claims more movement time than the budget holds.
	TOO_FAR,       ## Moved further than speed x tolerance x time allows.
}

## One sequence step is one 20 Hz send: 50 ms of movement.
const STEP_SEC: float = 0.05
const SPEED_TOLERANCE: float = 1.25
## The time budget starts full, refills at REFILL_RATE x real time, and caps here.
const BUDGET_MAX_SEC: float = 1.0
const BUDGET_REFILL_RATE: float = 1.1
const MAX_COORD: float = 100000.0
## Rounding slack, in pixels, so a move at exactly full speed passes.
const DISTANCE_SLACK: float = 0.01

var owner_id: int
var speed: float
var position: Vector2
var last_sequence: int = 0
var budget_sec: float = BUDGET_MAX_SEC
## Rejects since the hero spawned (wrong owner and old sequence not counted).
var rejected: int = 0

var _last_refill_sec: float


func _init(owner_peer: int, start_position: Vector2, move_speed: float, now_sec: float) -> void:
	owner_id = owner_peer
	position = start_position
	speed = move_speed
	_last_refill_sec = now_sec


## Checks one update. On ACCEPTED, position and last_sequence take the new values.
## On any other reject that counts, the position stays and last_sequence advances.
func check(sender_id: int, sequence: int, new_position: Vector2, now_sec: float) -> Result:
	if sender_id != owner_id:
		return Result.WRONG_OWNER
	if sequence <= last_sequence:
		return Result.OLD_SEQUENCE
	_refill(now_sec)
	var gap := sequence - last_sequence
	var result := _judge(gap, new_position)
	last_sequence = sequence
	if result == Result.ACCEPTED:
		budget_sec -= gap * STEP_SEC
		position = new_position
	else:
		rejected += 1
	return result


func _judge(gap: int, new_position: Vector2) -> Result:
	if not new_position.is_finite():
		return Result.NOT_FINITE
	if absf(new_position.x) > MAX_COORD or absf(new_position.y) > MAX_COORD:
		return Result.OUT_OF_BOUNDS
	var claimed_sec := gap * STEP_SEC
	if claimed_sec > budget_sec:
		return Result.OVER_BUDGET
	var allowed := speed * SPEED_TOLERANCE * claimed_sec + DISTANCE_SLACK
	if position.distance_to(new_position) > allowed:
		return Result.TOO_FAR
	return Result.ACCEPTED


func _refill(now_sec: float) -> void:
	var elapsed := maxf(0.0, now_sec - _last_refill_sec)
	_last_refill_sec = now_sec
	budget_sec = minf(BUDGET_MAX_SEC, budget_sec + elapsed * BUDGET_REFILL_RATE)


static func result_name(result: Result) -> String:
	return Result.keys()[result].to_lower().replace("_", " ")
