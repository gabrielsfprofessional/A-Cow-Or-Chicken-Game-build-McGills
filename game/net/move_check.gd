class_name MoveCheck
extends RefCounted
## The server's check on one hero's movement updates. Owner: Gabe (game/net). Cards T07, T14.
## Pure logic: the clock is passed in, so tests/move_check_test.gd can drive it.
## The position it keeps is the server's copy of the hero, which T08 hit-tests.
##
## T14: grant() adds extra distance for forced motion (a dash or a knockback).
## A move that goes further than walking allows draws the excess from the grant
## until it is used up or expires; drew_grant says whether the last accepted
## move did. reset() clears it.

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
## Extra distance, in pixels, moves may still draw on (T14).
var grant_px: float = 0.0
## True when the last accepted move drew on the grant.
var drew_grant: bool = false

var _last_refill_sec: float
var _grant_until_sec: float = -INF


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
	_expire_grant(now_sec)
	drew_grant = false
	var gap := sequence - last_sequence
	var result := _judge(gap, new_position)
	last_sequence = sequence
	if result == Result.ACCEPTED:
		var excess := position.distance_to(new_position) - _walk_allowed(gap)
		if excess > 0.0:
			grant_px = maxf(0.0, grant_px - excess)
			drew_grant = true
		budget_sec -= gap * STEP_SEC
		position = new_position
	else:
		rejected += 1
	return result


## Forced motion (T14): moves may go up to extra_px further than walking allows
## until until_sec. Grants add up and the later expiry wins. now_sec drops what
## is left of an expired grant first, so it never comes back.
func grant(extra_px: float, until_sec: float, now_sec: float) -> void:
	_expire_grant(now_sec)
	grant_px += maxf(0.0, extra_px)
	_grant_until_sec = maxf(_grant_until_sec, until_sec)


## Respawn (T08): the hero is back at new_position with a full budget and no grant.
## last_sequence and rejected stay: the owner's sequence never restarts.
func reset(new_position: Vector2, now_sec: float) -> void:
	position = new_position
	budget_sec = BUDGET_MAX_SEC
	_last_refill_sec = now_sec
	grant_px = 0.0
	drew_grant = false
	_grant_until_sec = -INF


func _judge(gap: int, new_position: Vector2) -> Result:
	if not new_position.is_finite():
		return Result.NOT_FINITE
	if absf(new_position.x) > MAX_COORD or absf(new_position.y) > MAX_COORD:
		return Result.OUT_OF_BOUNDS
	var claimed_sec := gap * STEP_SEC
	if claimed_sec > budget_sec:
		return Result.OVER_BUDGET
	if position.distance_to(new_position) > _walk_allowed(gap) + grant_px:
		return Result.TOO_FAR
	return Result.ACCEPTED


## How far `gap` sends of walking may go.
func _walk_allowed(gap: int) -> float:
	return speed * SPEED_TOLERANCE * gap * STEP_SEC + DISTANCE_SLACK


func _expire_grant(now_sec: float) -> void:
	if now_sec > _grant_until_sec:
		grant_px = 0.0


func _refill(now_sec: float) -> void:
	var elapsed := maxf(0.0, now_sec - _last_refill_sec)
	_last_refill_sec = now_sec
	budget_sec = minf(BUDGET_MAX_SEC, budget_sec + elapsed * BUDGET_REFILL_RATE)


static func result_name(result: Result) -> String:
	return Result.keys()[result].to_lower().replace("_", " ")
